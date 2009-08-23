package com.memamsa.airdb
{	
	/**
	*  Based on the Reflection.as by Jacob Wright (http://jacwright.com)
	*  Source - AIR ActiveRecord - 
	*  http://code.google.com/p/air-activerecord/source/browse/trunk/src/flight/utils/Reflection.as
	**/	
	import flash.utils.Dictionary;
	import flash.utils.describeType;
	import flash.utils.getDefinitionByName;
	
	/**
	* Utilities for introspecting class and object metadata through reflection.
	**/
	public class Reflector
	{
	  /**
	  * @internal Cache the metadata information for future lookups
	  **/
		protected static var cache:Dictionary = new Dictionary();
		
		/**
		* Looks up or gathers the XML metadata information for a specified object.
		* Caches the description for future lookup. 
		* 
		* @param obj An Object for which the metadata description is desired. When 
		* a String, XML or XMLList object is specified, dereferences the actual 
		* Object by looking up the corresponding class definition.
		* 
		* @return The XML description of the specified object
		* 
		* @see flash.utils#describeType
		* @see flash.utils#getDefinitionByName
		**/
		public static function describe(obj:Object):XML {
			if (obj is String || obj is XML || obj is XMLList) {
				obj = flash.utils.getDefinitionByName(obj.toString());
			} /*
      else if ( !(obj is Class) ) {
        obj = obj.constructor;
      } */
			if (obj in cache) {
				return cache[obj];
			}
			var info:XML = flash.utils.describeType(obj);		// factory[0]
			cache[obj] = info;
			return info;			
		}
		
		/**
		* Gets specific metadata information for the given object, including 
		* super classes if specified. 
		* 
		* @param obj The Object for which metadata lookup is required
		* 
		* @param metadata Specify the class or object metadata to lookup
		* 
		* @param includeSuperClasses Include super class metadata during lookup
		* @default true. 
		* 
		* @return XML description for the requested metadata
		* 
		* @see Reflector#describe
		* @see flash.utils#describeType
		**/
		public static function getMetadata(obj:Object, metadataType:String, includeSuperClasses:Boolean = false):XMLList {
			var info:XML = Reflector.describe(obj);		// flash.utils.describeType(obj); //
			var metadata:XMLList = info..metadata.(@name == metadataType);
			
			if (includeSuperClasses && info.extendsClass.length()) {
				metadata += getMetadata(info.extendsClass[0].@type, metadataType, true);
			}	
			return metadata;
		}

	}
}