package utils
{
	import flash.utils.ByteArray;
	
	import core.events.Event;
	import core.events.EventDispatcher;
	import core.events.IOErrorEvent;
	import core.events.ProgressEvent;
	import core.net.Socket;

	public class SocketCtrler extends EventDispatcher
	{
		protected var socket:Socket;
		protected var dataBuffer:ByteArray;
		protected var length:Number;
		protected var type:int;
		
		public function SocketCtrler(socket:Socket = null)
		{
			this.socket = socket;
			if(socket)
			{
				socket.addEventListener(Event.CONNECT, onConnected);
				socket.addEventListener(Event.CLOSE, onClose);
				socket.addEventListener(IOErrorEvent.IO_ERROR, onError);
				socket.addEventListener(ProgressEvent.SOCKET_DATA, onData);
			}
		}
		
		public function linkTo(host:String, port:int):void
		{
			if(socket && socket.connected)
			{
				socket.close();
			}
			else
			{
				socket = new Socket;
				socket.addEventListener(Event.CONNECT, onConnected);
				socket.addEventListener(Event.CLOSE, onClose);
				socket.addEventListener(IOErrorEvent.IO_ERROR, onError);
				socket.addEventListener(ProgressEvent.SOCKET_DATA, onData);
			}
			
			socket.connect(host, port);
		}
		
		public function close():void
		{
			socket.close();
			log("[Socket]本地断开");
		}
		
		protected function onConnected(e:Event):void
		{
			log("[Socket]已经连接");
		}
		
		protected function onClose(e:Event):void
		{
			log("[Socket]远程断开");
		}
		
		protected function onError(e:IOErrorEvent):void
		{
			log("[Socket]错误", e);
		}
		
		protected function onData(e:Event):void
		{
//			log("[Socket]接收到数据，长度", socket.bytesAvailable);
			
			while(socket.bytesAvailable)
			{
				
				if(!dataBuffer)
				{
					if(socket.bytesAvailable < 12)
						return;
					
					
					length = socket.readDouble();
					type = socket.readInt();
					dataBuffer = new ByteArray;
				}
				
				if(socket.bytesAvailable < length)
				{
					return;
				}

				socket.readBytes(dataBuffer, 0, length);
				dispatchEvent(new SocketEvent("data", dataBuffer, type));
				dataBuffer = null;
				//如果使用立即模式，并且在dispatchEvent后本地断开连接，则再次循环执行socket.bytesAvailable时会因为socket已经关闭而报错。
				if(!socket.connected)
				{
					return;
				}
					
			}
		}
		
		public function send(data:ByteArray, type:int):void
		{
			if(!socket || !socket.connected)
			{
				log("[Socket]尚未连接，无法发送");
			}
			
			socket.writeDouble(data.length);
			socket.writeInt(type);
			socket.writeBytes(data);
			
			socket.flush();
		}
	}
}