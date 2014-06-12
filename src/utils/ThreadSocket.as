package utils
{
	import flash.concurrent.Mutex;
	import flash.utils.ByteArray;
	import flash.utils.IDataInput;
	import flash.utils.IDataOutput;
	
	import core.events.Event;
	import core.events.EventDispatcher;
	import core.events.ProgressEvent;
	import core.events.TimerEvent;
	import core.system.Worker;
	import core.utils.Timer;
	
	/**
	 * 使用类似Socket的接口进行线程间的通讯
	 * <br>必须将事件派发模式设为立即模式。即EventDispatcher.immediateMode设为true
	 * <br>除主线程外，创建ThreadSocket必须提供虚拟Timer。
	 * <br>请使用writeShareByteArray和readShareByteArray传输共享模式的字节数组。
	 * <br>以此方法传输共享模式的字节数组时，其数据通道不和其他数据传输共享，因而可以不遵循固定的读写顺序。
	 * <br>使用writeBytes和readBytes传输共享模式的字节数组时，将传输拷贝而不是引用。
	 * <br>不能指定
	 * @author wangyu
	 * 
	 */
	public class ThreadSocket extends EventDispatcher implements IDataInput, IDataOutput
	{
		/**本地读缓存*/		
		protected var localReadBuffer:ByteArray;
		/**本地写缓存*/
		protected var localWriteBuffer:ByteArray;
		/**本地读共享字节数组集合*/
		protected var localReadShare:Vector.<ByteArray>;
		/**本地写共享字节数组集合*/
		protected var localWriteShare:Vector.<ByteArray>;
		/**共享的读缓存*/
		protected var sharedReadBuffer:ByteArray;
		/**共享的写缓存*/
		protected var sharedWriteBuffer:ByteArray;
		/**共享的读字节数组命名前缀*/
		protected var sharedReadSharePrefix:String;
		/**共享的写字节数组命名前缀*/
		protected var sharedWriteSharePrefix:String;
		/**读命令通道*/
		protected var readCmdLine:ByteArray;
		/**写命令通道*/
		protected var writeCmdLine:ByteArray;
		/**读锁*/
		protected var readMutex:Mutex;
		/**写锁*/
		protected var writeMutex:Mutex;
		/**
		 * 虚拟计时器。
		 * 在主线程中，他是Timer实例，
		 * 在子线程中，他是虚拟计时器
		 */
		protected var vTimer:EventDispatcher;
		protected var _port:int;
		protected var _connected:Boolean;
		/**指示连接是否为服务器端。*/
		protected var _isServer:Boolean;
		/**远程线程*/
		protected var remoteWorker:Worker;
		
		/**指示正在侦听哪个端口*/
		protected static const LISTENING:String = "ThreadConstsListing";
		/**端口连接Mutex，成功的lock此Mutex者获得此连接*/
		protected static const CONNECT_MUTEX:String = "ThreadConstsConnectMutex_";
		/**C到S的缓冲区*/
		protected static const C2S_BUFFER:String = "ThreadConstsC2SBuffer_";
		/**S到C的缓冲区*/
		protected static const S2C_BUFFER:String = "ThreadConstsS2CBuffer_";
		/**C到S的共享字节数组命名区域*/
		protected static const C2S_SHARE:String = "ThreadConstsC2SShare_";
		/**S到C的共享字节数组命名区域*/
		protected static const S2C_SHARE:String = "ThreadConstsS2CShare_";
		/**C到S的读写锁*/
		protected static const C2S_MUTEX:String = "ThreadConstsC2SMutex_";
		/**S到C的读写锁*/
		protected static const S2C_MUTEX:String = "ThreadConstsS2CMutex_";
		/**C到S的命令通道*/
		protected static const C2S_CMD:String = "ThreadConstsC2SCommand";
		/**S到C的命令通道*/
		protected static const S2C_CMD:String = "ThreadConstsS2CCommand";
		/**命令：关闭连接*/
		protected static const CMD_CLOSE:int = 1;
		/**可容忍的读缓冲区最大已读长度。当已读的数据超过此长度时，下一次接收数据就会清理缓冲区中的已读数据*/
		protected static const BUFFER_CLEAN_LENGTH:int = 32768;
		/**建议的计时器延迟。使用此延迟在CPU占用和响应延迟间取得平衡*/
		public static const SUGGESTED_TIMER_DELAY:int = 10;
		
		/**本地线程*/
		protected static const localWorker:Worker = Worker.current;
		
		/**本地线程*/
		protected static var isListening:Boolean = Worker.current;
		
		
		/**本地线程是否为主线程*/
		public static const isPrimordial:Boolean = Worker.current.isPrimordial;
		
		{
			if(!isPrimordial && !EventDispatcher.immediateMode)
			{
				throw new Error("子线程中的ThreadSocket无法在队列模式下执行")
			}
		}
		
		/**
		 * 创建一个ThreadSocket
		 * @param vTimer 虚拟Timer。对于主线程，它是一个Timer；
		 * <br>对于子线程，由于无法使用Timer，它是一个会每隔一段时间派发TimerEvent.TIMER事件的对象。
		 * 
		 */
		public function ThreadSocket(vTimer:EventDispatcher = null)
		{
			//确认Timer
			if(vTimer)
			{
				this.vTimer = vTimer;
			}
			else
			{
				if(isPrimordial)
				{
					this.vTimer = new Timer(SUGGESTED_TIMER_DELAY);
					(this.vTimer as Timer).start();
				}
				else
				{
					throw new Error("在子線程中執行listen需要提供虛擬Timer。");
				}
			}
			
			init();
			
		}
		
		protected function init():void
		{
			
			//准备好读写缓冲区 以便可以随时读写。在连接成功之前也可以读写。
			localReadBuffer = new ByteArray;
			localWriteBuffer = new ByteArray;
			localReadShare = new Vector.<ByteArray>;
			localWriteShare = new Vector.<ByteArray>;
			
			//准备一些需要本端口创建的共享对象
			sharedWriteBuffer = new ByteArray;
			sharedWriteBuffer.shareable = true;
			writeCmdLine = new ByteArray;
			writeCmdLine.shareable = true;
			writeMutex = new Mutex;
			
			//清除不需要的对象引用
			sharedReadBuffer = null;
			readMutex = null;
			readCmdLine = null;
		}
		
		/**
		 */
		/**
		 *开始侦听连接。
		 * <br>与Socket协议不同，连接时无法指定端口号。
		 * <br>連接成功後將停止偵聽，并拋出連接成功事件
		 * <br>
		 * <br>过程：
		 * <br>监听端S决定连接端口，在该端口放置Mutex连接标识、S2C缓冲区、S2C读写锁，在LISTENING放置端口号
		 * <br>连接端C检测LISTENING指定的端口号，并尝试锁定指定端口的Mutex。
		 * <br>如果C成功锁定了指定端口的Mutex，则在该端口上放置C发送S接收缓冲区。C抛出连接成功事件。
		 * <br>S检测到C发送S接收缓冲区已经放置，则在该端口上放置S发送C接收缓冲区。S抛出连接成功事件。S清除LISTENING，表示不再处于侦听状态。
		 * <br>
		 */
		public function listen():void
		{
			
			//确定端口
			_port = Math.random() * 1000;
			//设置端口锁，避免多个客户端连接竞争同一个端口
			localWorker.setSharedProperty(CONNECT_MUTEX + _port, new Mutex);
			//设置S到C的通讯共享对象
			localWorker.setSharedProperty(S2C_MUTEX + _port, writeMutex);
			localWorker.setSharedProperty(S2C_BUFFER + _port, sharedWriteBuffer);
			localWorker.setSharedProperty(S2C_CMD + _port, writeCmdLine);
			//设置共享字节数组的命名前缀
			sharedReadSharePrefix = C2S_SHARE + _port + "_";
			sharedWriteSharePrefix = S2C_SHARE + _port + "_";
			//最后写入端口，这个操作一旦完成就可以连上了
			localWorker.setSharedProperty(LISTENING, _port);
			
			//检测连接完成
			vTimer.addEventListener(TimerEvent.TIMER, onTimerListen);
		}
		
		protected function onTimerListen(e:Event):void
		{
			//检测是否已经连接，看C到S的读写锁是否已经就位
			if(localWorker.getSharedProperty(C2S_MUTEX + _port) is Mutex)
			{
				vTimer.removeEventListener(TimerEvent.TIMER, onTimerListen);
				//清理端口指示
				localWorker.setSharedProperty(LISTENING, undefined);
				//获得C到S的通讯共享对象
				readMutex = localWorker.getSharedProperty(C2S_MUTEX + _port);
				sharedReadBuffer = localWorker.getSharedProperty(C2S_BUFFER + _port);
				readCmdLine = localWorker.getSharedProperty(C2S_CMD + _port);
				
				_connected = true;
				_isServer = true;
				
				//添加下载监视
				vTimer.addEventListener(TimerEvent.TIMER, trySend);
				vTimer.addEventListener(TimerEvent.TIMER, tryReceive);
				//派发连接成功事件
				trace("连接到客户端", _port);
				dispatchEvent( new Event(Event.CONNECT) );
			}
		}
		
		/**
		 * 尝试连接到指定的Worker。这是一个同步操作。
		 * 
		 * 过程：
		 * <br>检查worker的LISTENING，如果为空则连接失败。
		 * <br>尝试锁定LISTENING所指定端口的Mutex。如果锁定失败则连接失败。
		 * <br>如果锁定成功，则放置发送缓冲区，连接成功。
		 */
		public function connect(worker:Worker):Boolean
		{
			if(_connected)
			{
				return false;
			}
			//检查目标worker是否指定了连接端口
			if(worker.getSharedProperty(LISTENING) is int)
			{
				_port = worker.getSharedProperty(LISTENING);
				//尝试锁定连接端口
				var mutex:Mutex = worker.getSharedProperty(CONNECT_MUTEX + _port) as Mutex;
				if(mutex && mutex.tryLock())
				{
					remoteWorker = worker;
					//设置共享字节数组的命名前缀
					sharedReadSharePrefix = S2C_SHARE + _port + "_";
					sharedWriteSharePrefix = C2S_SHARE + _port + "_";
					//获得S到C的通讯共享对象
					readMutex = worker.getSharedProperty(S2C_MUTEX + _port);
					sharedReadBuffer = worker.getSharedProperty(S2C_BUFFER + _port);
					readCmdLine = worker.getSharedProperty(S2C_CMD + _port);
					//设置C到S的通讯共享对象
					worker.setSharedProperty(C2S_BUFFER + _port, sharedWriteBuffer);
					worker.setSharedProperty(C2S_CMD + _port, writeCmdLine);
					//最后设置C到S的读写锁。这是客户端已经连接的标识。
					worker.setSharedProperty(C2S_MUTEX + _port, writeMutex);
					
					_connected = true;
					_isServer = false;
					//添加下载监视
					vTimer.addEventListener(TimerEvent.TIMER, trySend);
					vTimer.addEventListener(TimerEvent.TIMER, tryReceive);
					//连接成功
					return true;
				}
			}
			return false;
		}
		
		/**
		 *将写缓冲区的内容送出。 
		 * 如果并未连接成功，则什么也不做。
		 */
		public function flush():void
		{
		}
		
		protected function trySend(e:Event = null):Boolean
		{
			//尝试获得写锁
			if(0 == localWriteShare.length && 0 == localWriteBuffer.length)
			{
				return true;
			}
			
			if(!writeMutex.tryLock())
			{
				return false;
			}
			
			var targetWorker:Worker = _isServer ? localWorker : remoteWorker;
			//追加共享字节数组
			var n:int = targetWorker.getSharedProperty(sharedReadSharePrefix);
			targetWorker.setSharedProperty(sharedReadSharePrefix, localWriteShare.length + n);
			for(var i:int = localWriteShare.length - 1; i >= 0; i--)
			{
				targetWorker.setSharedProperty(sharedReadSharePrefix + (i + n), localWriteShare[i]);
			}
			localWriteShare.length = 0;
			//追加写缓存
			//谨记，不同线程中共享的ByteArray虽然共享相同的数据内存，但仍然是不同的两个对象。因而其读写头position不会同步。
			//使写buffer的读写头处于正确的追加位置。这确保了写buffer被对方读空后，本地的读写头可以归零。
			sharedWriteBuffer.position = sharedWriteBuffer.length;
			sharedWriteBuffer.writeBytes(localWriteBuffer)
			localWriteBuffer.clear();
			//释放写锁
			writeMutex.unlock();
			
			
			
			return true;
		}
		
		protected function tryReceive(e:Event = null):Boolean
		{
			//尝试获得读锁
			if(!readMutex.tryLock())
			{
				return false;
			}
			var targetWorker:Worker = _isServer ? localWorker : remoteWorker;
			/**表示接收消息后是否需要断开连接*/
			var needClose:Boolean;
			//读取命令通道
			while(readCmdLine.bytesAvailable)
			{
				switch(readCmdLine.readUnsignedInt())
				{
					case CMD_CLOSE:
					{
						//TODO
						needClose = true;
						break;
					}
						
					default:
					{
						break;
					}
				}
				readCmdLine.clear();
			}
			//读取共享字节数组
			var length:int = targetWorker.getSharedProperty(sharedWriteSharePrefix);
			targetWorker.setSharedProperty(sharedWriteSharePrefix, 0);
			var i:int;
			for(i = 0; i < length; i++)
			{
				localReadShare.push(targetWorker.getSharedProperty(sharedWriteSharePrefix + i));
				targetWorker.setSharedProperty(sharedWriteSharePrefix + i, undefined);
			}
			//读取共享读缓存
			if(sharedReadBuffer.length)
			{
				//如果本地读Buffer的已读部分过长，则先清理本地Buffer
				if(localReadBuffer.position > BUFFER_CLEAN_LENGTH)
				{
					var newBuffer:ByteArray = new ByteArray;
					newBuffer.writeBytes(localReadBuffer);
					
					localReadBuffer.clear();
					localReadBuffer = newBuffer;
				}
				
				//追加共享读缓存
				var temp:uint = localReadBuffer.position;
				localReadBuffer.writeBytes(sharedReadBuffer);
				localReadBuffer.position = temp;
				sharedReadBuffer.clear();
			}
			readMutex.unlock();
			
			//派发事件必须在最后执行。因为一旦用户在事件处理器中做了什么比如断开连接之类的操作，很多东西就失效了
			if(length || localReadBuffer.bytesAvailable)
			{
				dispatchEvent(new ProgressEvent(ProgressEvent.SOCKET_DATA, false, localReadBuffer.bytesAvailable, localReadBuffer.length));
			}
			
			if(needClose && _connected)
			{
				_connected = false;
				init();
				vTimer.removeEventListener(TimerEvent.TIMER, trySend);
				vTimer.removeEventListener(TimerEvent.TIMER, tryReceive);
				dispatchEvent(new Event(Event.CLOSE));
			}
			
			return true;
		}
		
		public function close():void
		{
			//写入关闭指令
			writeMutex.lock();
			writeCmdLine.writeUnsignedInt(CMD_CLOSE);
			writeMutex.unlock();
			
			//主动断开者负责清理共享对象
			var targetWorker:Worker = _isServer ? localWorker : remoteWorker;
			//清理双方的通讯共享对象
			targetWorker.setSharedProperty(S2C_MUTEX + _port, undefined);
			targetWorker.setSharedProperty(S2C_BUFFER + _port, undefined);
			targetWorker.setSharedProperty(S2C_CMD + _port, undefined);
			targetWorker.setSharedProperty(C2S_MUTEX + _port, undefined);
			targetWorker.setSharedProperty(C2S_BUFFER + _port, undefined);
			targetWorker.setSharedProperty(C2S_CMD + _port, undefined);
			//清理连接锁，但是不unlock连接锁。以免连接迅速建立而后销毁，另一个连接在连接建立之前引用连接锁，而在连接销毁之后才检测连接锁。
			targetWorker.setSharedProperty(CONNECT_MUTEX + _port, undefined);
			
			vTimer.removeEventListener(TimerEvent.TIMER, trySend);
			vTimer.removeEventListener(TimerEvent.TIMER, tryReceive);
			//一些清理操作
			_connected = false;
			init();
		}
		
		public function readBytes(bytes:ByteArray, offset:uint=0, length:uint=0):void
		{
			localReadBuffer.readBytes(bytes, offset, length);
		}
		
		public function readShareByteArray():ByteArray
		{
			return localReadShare.shift();
		}
		
		public function readBoolean():Boolean
		{
			return localReadBuffer.readBoolean();
		}
		
		public function readByte():int
		{
			return localReadBuffer.readByte();
		}
		
		public function readUnsignedByte():uint
		{
			return localReadBuffer.readUnsignedByte();
		}
		
		public function readShort():int
		{
			return localReadBuffer.readShort();
		}
		
		public function readUnsignedShort():uint
		{
			return localReadBuffer.readUnsignedShort();
		}
		
		public function readInt():int
		{
			return localReadBuffer.readInt();
		}
		
		public function readUnsignedInt():uint
		{
			return localReadBuffer.readUnsignedInt();
		}
		
		public function readFloat():Number
		{
			return localReadBuffer.readFloat();
		}
		
		public function readDouble():Number
		{
			return localReadBuffer.readDouble();
		}
		
		public function readMultiByte(length:uint, charSet:String):String
		{
			return localReadBuffer.readMultiByte(length, charSet);
		}
		
		public function readUTF():String
		{
			return localReadBuffer.readUTF();
		}
		
		public function readUTFBytes(length:uint):String
		{
			return localReadBuffer.readUTFBytes(length);
		}
		
		public function get bytesAvailable():uint
		{
			return localReadBuffer.bytesAvailable;
		}
		
		public function get shareByteArraysAvailable():uint
		{
			return localReadShare.length;
		}
		
		public function readObject():*
		{
			return localReadBuffer.readObject();
		}
		
		public function get objectEncoding():uint
		{
			return localReadBuffer.objectEncoding;
		}
		
		public function set objectEncoding(version:uint):void
		{
//			localReadBuffer.objectEncoding = version;
//			localWriteBuffer.objectEncoding = version;
			throw new Error("不允许进行此操作");
		}
		
		public function get endian():String
		{
			return localReadBuffer.endian;
		}
		
		public function set endian(type:String):void
		{
			throw new Error("不允许进行此操作");
		}
		
		public function writeBytes(bytes:ByteArray, offset:uint=0, length:uint=0):void
		{
			localWriteBuffer.writeBytes(bytes, offset, length);
		}
		
		public function writeShareByteArray(bytes:ByteArray):void
		{
			if(!bytes.shareable)
			{
				throw new Error("字节数组不是可共享的");
			}
			localWriteShare.push(bytes);
		}
		
		public function writeBoolean(value:Boolean):void
		{
			localWriteBuffer.writeBoolean(value);
		}
		
		public function writeByte(value:int):void
		{
			localWriteBuffer.writeByte(value);
		}
		
		public function writeShort(value:int):void
		{
			localWriteBuffer.writeShort(value);
		}
		
		public function writeInt(value:int):void
		{
			localWriteBuffer.writeInt(value);
		}
		
		public function writeUnsignedInt(value:uint):void
		{
			localWriteBuffer.writeUnsignedInt(value);
		}
		
		public function writeFloat(value:Number):void
		{
			localWriteBuffer.writeFloat(value);
		}
		
		public function writeDouble(value:Number):void
		{
			localWriteBuffer.writeDouble(value);
		}
		
		public function writeMultiByte(value:String, charSet:String):void
		{
			localWriteBuffer.writeMultiByte(value, charSet);
		}
		
		public function writeUTF(value:String):void
		{
			localWriteBuffer.writeUTF(value);
			trace("本地数据长度", localWriteBuffer.length)
		}
		
		public function writeUTFBytes(value:String):void
		{
			localWriteBuffer.writeUTFBytes(value);
		}
		
		public function writeObject(object:*):void
		{
			localWriteBuffer.writeObject(object);
		}
		
		public override function dispose():void
		{
			//todo
		}

		/**指示连接是否已经建立。*/
		public function get connected():Boolean
		{
			return _connected;
		}

		/**指示连接所使用的端口。*/
		public function get port():int
		{
			return _port;
		}


	}
}