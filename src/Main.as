package
{
	import core.display.DisplayObjectContainer;
	import core.events.Event;
	import core.events.EventDispatcher;
	import core.events.ProgressEvent;
	import core.system.System;
	import core.system.Worker;
	import core.system.WorkerDomain;
	
	import utils.ThreadSocket;
	
	public class Main extends DisplayObjectContainer
	{
		public function Main(...args)
		{
			
			//显式引用ThreadMain以便其编译。
			ThreadMain;
			
			/**
			 * 多线程将创建一个默认包中的"ThreadMain"类的实例。
			 * 可以从当前执行文件或者指定的文件载入。
			 * 该类构造函数原型：public function ThreadMain(args:String = '')。
			 * 相比原生多线程，本平台多线程有如下限制：
			 * 1.不提供MessageChannel
			 * 2.只有原始线程可以使用事件队列。这意味着：
			 * 	1)在子线程中，当事件模式设为队列模式时，所有用户派发的事件都被忽略。
			 * 	2)任何系统派发的事件都无法使用，包括但不限于触摸事件、网络事件、感应器事件、Timer。
			 * 	3)实际上，在此版本中，在子线程中尝试向命令队列派发事件会导致崩溃。
			 * 请参阅默认包中的"ThreadMain"类获取更多信息。
			 * 
			 * 以下是要点：
			 * 1.保证ThreadMain主类构造方法的持续运行。一旦此方法运行完成，线程将被回收。
			 * 
			 */
			
			//从当前可执行文件创建线程对象。
			var worker:Worker = WorkerDomain.current.createWorkerFromPrimordial();
			worker.start();
			//等待worker启动。参阅默认包中的"ThreadMain"类
			while(!worker.getSharedProperty("ready"))
			{
			}
			
			//从其他可执行文件创建线程对象
			//			var worker2:Worker = WorkerDomain.current.createWorkerFromByteArray(File.readByteArray("Main.swf"));
			////			worker2.setSharedProperty("condition", condition);
			//			worker2.start();
			//			while(!worker2.getSharedProperty("ready"))
			//			{
			//			}
			//			condition.wait();
			
			//枚举当前的所有线程，包含主线程
			trace("总线程数：", WorkerDomain.current.listWorkers().length);
			trace("主线程index：", WorkerDomain.current.listWorkers().indexOf(Worker.current));
			trace(WorkerDomain.current.listWorkers()[1].state);
			System.sleep(1000);
			trace("主线程index：", WorkerDomain.current.listWorkers().indexOf(Worker.current));
			trace(EventDispatcher.immediateMode);
			
			var ts:ThreadSocket = new ThreadSocket;
			ts.addEventListener(Event.CONNECT, onConnected);
			ts.addEventListener(ProgressEvent.SOCKET_DATA, onData);
			ts.addEventListener(Event.CLOSE, onClose);
			function onData(e:Event):void
			{
				if((e.target as ThreadSocket).bytesAvailable)
				{
					trace("接收到消息", (e.target as ThreadSocket).readUTF());
				}
				if((e.target as ThreadSocket).shareByteArraysAvailable)
				{
					trace("接收到字节数组", (e.target as ThreadSocket).shareByteArraysAvailable);
					if(100 == (e.target as ThreadSocket).shareByteArraysAvailable)
						while((e.target as ThreadSocket).shareByteArraysAvailable)
							(e.target as ThreadSocket).readShareByteArray();
				}
				ts.writeUTF("你好客户端");
				ts.flush();
			}
			function onClose(e:Event):void
			{
				trace("客户端断开连接");
				ts.listen();
			}
			function onConnected(e:Event):void
			{
				trace("检测到客户端的连接")
			}
			ts.listen();
			
			
			/**
			 * 简单的线程间协同工作可以直接使用共享属性。
			 */
			
			
			/**
			 * 如果要进行复杂的协同工作，执行多种指令，
			 * 可以使用类似网络协议的方式进行通讯。
			 * 并使用共享锁确保数据不被同时读写。
			 */
			
		}
	}
}