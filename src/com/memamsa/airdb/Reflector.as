package com.memamsa.airdb
{
	import flash.utils.Dictionary;
	import flash.utils.describeType;
	import flash.utils.getDefinitionByName;
	
	public class Reflector
	{
		protected static var cache:Dictionary = new Dictionary();
		
		public static function describe(obj:Object):XML {
			if (obj is String || obj is XML || obj is XMLList) {
				obj = flash.utils.getDefinitionByName(obj.toString());
			} 
//			else if ( !(obj is Class) ) {
//				obj = obj.constructor;
//			}
			if (obj in cache) {
				return cache[obj];
			}
			var info:XML = flash.utils.describeType(obj);		// factory[0]
			cache[obj] = info;
			return info;			
		}
		
		public static function getMetadata(obj:Object, metadataType:String, includeSuperClasses:Boolean = false):XMLList {
			var info:XML = Reflector.describe(obj);		// flash.utils.describeType(obj); //
			var metadata:XMLList = info..metadata.(@name == metadataType);
//			trace('metadata: ' + metadata);
			
			if (includeSuperClasses && info.extendsClass.length()) {
				metadata += getMetadata(info.extendsClass[0].@type, metadataType, true);
			}	
			return metadata;
		}

	}
}