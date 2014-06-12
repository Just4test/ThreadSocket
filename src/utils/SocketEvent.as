package utils
{
	import flash.utils.ByteArray;
	
	import core.events.Event;

	public class SocketEvent extends Event
	{
		public var data:ByteArray;
		public var dataType:int;
		
		public function SocketEvent(type:String, data:ByteArray, dataType:int)
		{
			super(type, false);
			this.data = data;
			this.dataType = dataType;
		}
	}
}