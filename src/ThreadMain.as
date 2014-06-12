package
{
import flash.utils.ByteArray;

import core.display.DisplayObjectContainer;
import core.events.Event;
import core.events.ProgressEvent;
import core.events.TimerEvent;
import core.system.System;
import core.system.Worker;
import core.system.WorkerDomain;
import core.utils.Timer;
import utils.ThreadSocket;


/**
 *用于启动子线程。 
 */
public class ThreadMain extends DisplayObjectContainer
{
	protected var timer:Timer;
    public function ThreadMain(args:String = ''):void
    {
		immediateMode = true;
		trace("线程已经启动！当前线程index：", WorkerDomain.current.listWorkers().indexOf(Worker.current));
		Worker.current.setSharedProperty("ready", true);
		
		var test:ByteArray = new ByteArray;
		test.writeUTFBytes("0123456789qwerty");
		test.position = 5;
		trace("@@@@", test.readUTFBytes(test.bytesAvailable));
		test.position = 5;
		test.readBytes(test);
		trace("@@@@", test.readUTFBytes(test.bytesAvailable));
		
		
		var ts:ThreadSocket = new ThreadSocket(this);
		ts.addEventListener(ProgressEvent.SOCKET_DATA, onData);
		function onData(e:Event):void
		{
			if((e.target as ThreadSocket).bytesAvailable)
			{
				trace("接收到消息", (e.target as ThreadSocket).readUTF());
			}
			if((e.target as ThreadSocket).shareByteArraysAvailable)
			{
				trace("接收到字节数组", (e.target as ThreadSocket).shareByteArraysAvailable);
			}
			var temp:ByteArray = new ByteArray;
			temp.shareable = true;
			ts.writeShareByteArray(temp);
		}
		while(!ts.connected)
		{
			System.sleep(300);
			trace("尝试连接")
			ts.connect(WorkerDomain.current.listWorkers().pop());
		}
		trace("成功连接到服务器！")
		var temp:ByteArray = new ByteArray;
		temp.shareable = true;
		ts.writeShareByteArray(temp);
		
		while(true)
		{
			dispatchEvent(new Event(TimerEvent.TIMER));
			System.sleep(ThreadSocket.SUGGESTED_TIMER_DELAY);
		}
    }
}
}