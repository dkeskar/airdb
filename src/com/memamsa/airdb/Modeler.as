package com.memamsa.airdb
{
	/**
	 * Basic Object Relation Modeling
	 * data, load, create, update, delete, save, find
	 **/
	import flash.data.SQLResult;
	import flash.data.SQLStatement;
	import flash.errors.SQLError;
	import flash.utils.Proxy;
	import flash.utils.flash_proxy;
	import flash.utils.getDefinitionByName;
	import flash.utils.getQualifiedClassName;
	
	public class Modeler extends Proxy
	{
		// Note: Migrator puts following on the Modeler class prototype
		// fieldNames - An Array of field names 
		// storeName - the DB table associated with this Model.
		 
		// The field values found, updated or created
		private var newRecord:Boolean;
		private var recLoaded:Boolean;
		private var recChanged:Boolean;
		private var fieldsChanged:Object = {};
		private var mStoreName:String = null;
		private var stmt:SQLStatement = null;
		
		// sub-class(es) can access fieldValues directly (if they need to) 
		protected var fieldValues:Object = new Object();
		
		// associations
		private var associations:Object = {};
		
		public function Modeler()
		{
			stmt = new SQLStatement();
			stmt.sqlConnection = DB.getConnection();

			var fqName:String = flash.utils.getQualifiedClassName(this);
			var model:Class = flash.utils.getDefinitionByName(fqName) as Class;
			mStoreName = model.prototype.storeName; 
			for each (var fname:* in model.prototype.fieldNames) {
				fieldValues[fname] = null;
			}
			// new ModelClass() is for creating new record
			newRecord = true;
		}
		
		// initialize this object to hold fields for a new record. 
		public function data(values:Object):void {
			if (!values) return;
			resetFields();			
			
			for (var key:String in values) {
				if (fieldValues.hasOwnProperty(key)) {
					fieldValues[key] = values[key];
				} else {
					trace('data: unknown field: ' + key);
					throw 'FieldUnknown';
				}
			}
			// TODO: add check if primary id is being set
			newRecord = true;
		}

		// save newly initialized or modified data
		public function save():Boolean {
			if (!newRecord && !recChanged) return false;
			return (newRecord ? create() : update());
		}

		// finds a record matching specified field values and load
		// this object properties with field values from the record.
		// if found returns true 
		public function load(keyvals:Object):Boolean {
			resetFields();
			if (!keyvals) return false;
				
			var conditions:Array = [];
			stmt.text = "SELECT * FROM " + mStoreName + " WHERE ";
			for (var key:String in keyvals) {
				var clause:String = "";
				if (!fieldValues.hasOwnProperty(key)) {
					trace('find: unknown field ' + key + ' in condition properties');
					throw "FieldUnknown: " + key;
				}
				clause += key + ' = ' + DB.sqlMap(keyvals[key]);
				conditions.push(clause);
			}
			stmt.text += conditions.join(' AND ');
			try {
				stmt.execute();
				var result:SQLResult = stmt.getResult();
				if (!result || !result.data) {
					trace('find: no rows');
					return false;
				}
				if (result.data.length > 0) {
					// we trust the DB schema so whole new assignment is ok.
					fieldValues = result.data[0];
					newRecord = false;
					recLoaded = true;
				}
			} catch (error:SQLError) {
				trace("ERROR: find: " + error.details);
				return false;
			}
			return true;
		}
		
		// Find using query predicates provided
		// The query object keys supported are the SQL clauses: 
		// conditions, group, order, limit, joins 
		public function findAll(query: Object):Array {
			resetFields();
			stmt.text = constructSql(query);
			try {
				stmt.execute();
				var result:SQLResult = stmt.getResult();
				if (!result || !result.data) {
					trace('findall: query returned zero results');
					return [];
				}
				return result.data;
			} catch (error:SQLError) {
				trace('ERROR:findall: ' + error.details);
			}
			return [];	
		}

		// Count of the number of records
		public function count():int {
			resetFields();
			stmt.text = "SELECT COUNT(*) as count FROM " + mStoreName;
			try {
				stmt.execute();
				var result:SQLResult = stmt.getResult();
				if (result && result.data && result.data.length >= 1) {
					return result.data[0].count;
				}
				trace('count: cannot interpret result'); 
			} catch (error:SQLError) {
				trace("ERROR: count: " + error.details);
			}
			return -1;
		}
		
		public function countAll(query:Object):int {
			query.select = "COUNT(*) as count_all";
			stmt.text = constructSql(query);
			try {
				stmt.execute();
				var result:SQLResult = stmt.getResult();
				if (result && result.data && result.data.length >= 1) {
					return result.data[0].count_all;
				}
				trace('countAll: cannot interpret result');
			} catch (error:SQLError) {
				trace('ERROR: countAll: ' + error.details);
			}
			return -1;
		}

		// create a record with given values (or using object values)
		public function create(values:Object=null):Boolean {
			if (!values && !newRecord) return false;
			var key:String;
			if (!values && newRecord) {
				values = fieldValues;
			}
			stmt.text = "INSERT INTO " + mStoreName;
			var cols:Array = [];
			var vals:Array = [];
			timeStamp('created_at', values);
			for (key in values) {
				if (!fieldValues.hasOwnProperty(key)) {
					trace('create: unknown fields specified');
					throw "FieldUnknown";
				}
				if (values[key] == null) continue;
				cols.push(key);
				vals.push(DB.sqlMap(values[key]));
				fieldValues[key] = values[key];
			}
			stmt.text += " (" + cols.join(',') + ")";
			stmt.text += " VALUES (" + vals.join(',') + ")";
			try {
				stmt.execute();
				var result:SQLResult = stmt.getResult();
				if (result && result.complete) {
					fieldValues['id'] = result.lastInsertRowID;
				}
			} catch (error:SQLError) {
				trace("ERROR: create: " + error.details);
				return false;
			}
			newRecord = false;			
			return true;
		}
		
		// update currently loaded/init'd record with new values		
		public function update(values:Object=null):Boolean {
			if (!values && !recChanged) return false;
			// new records should be "created"
			if (!values && (newRecord || !fieldValues['id'])) {
			  throw mStoreName + ".update: Expected create";
		  }

			var assigns:Array = [];
			var key:String;
			var changed:Boolean = recChanged;
			
			for (key in values) {
				if (!fieldValues.hasOwnProperty(key)) {
					trace('update: unknown field: ' + key);
					throw 'FieldUnknown';
				}
				if (values[key] && fieldValues[key] != values[key] && key != 'id') {
					fieldValues[key] = values[key];
					changed = true;
					fieldsChanged[key] = true;
				}
			}
			if (changed) {
				for (key in fieldsChanged) {
					assigns.push(key + " = " + DB.sqlMap(fieldValues[key]));
				}
				stmt.text = "UPDATE " + mStoreName + " SET ";
				stmt.text += assigns.join(',');
				if (recLoaded || (values && values.hasOwnProperty('id'))) {
					stmt.text += " WHERE id = " + ((values && values['id']) || fieldValues['id']).toString(); 
				}
				try {
					stmt.execute();
				} catch (error:SQLError) {
					trace("Error: update: " + error.details);
					return false;
				}
				// upon successful update, reflect new values in this object
				recChanged = false;
				fieldsChanged = {};
			}
			return true;
		}
		
		// Update all records matching conditions
		// Returns the number of records updated 
		public function updateAll(conditions:String, values:Object):uint {
			resetFields();
			stmt.text = "UPDATE " + mStoreName + " SET ";
			var assigns:Array = [];
			for (var key:String in values) {
				if (!fieldValues.hasOwnProperty(key)) {
					trace('update: unknown field: ' + key);
					throw 'FieldUnknown';
				}
				assigns.push(key + ' = ' + DB.sqlMap(values[key]));
			}
			stmt.text += assigns.join(',');
			if (conditions) {
				stmt.text += " WHERE " + conditions;
			}
			try {
				stmt.execute();
				var result:SQLResult = stmt.getResult();
				if (!result || !result.data || !result.data.rowsAffected) {
					trace('updateAll: update failed');
					return 0;
				}
				return result.data.rowsAffected;				
			} catch (error:SQLError) {
				trace('Error: updateAll: ' + error.details);
				return 0;
			}
			return 0;
		}
		
		/** 
		 * Property Overrides to handle column names and associations 
		 **/
		override flash_proxy function hasProperty(name:*):Boolean {
			// TODO: also check associations meta-data
			return fieldValues.hasOwnProperty(name);
		} 
		
		override flash_proxy function getProperty(name:*):* {
			name = name.toString();
			if (name == 'storeName') return mStoreName;
						
			if (fieldValues.hasOwnProperty(name)) {
				return fieldValues[name];
			}
			if (name in associations) {
				return associations[name];
			}
			
			var assocList:XMLList = Reflector.getMetadata(this, "Association");
			for (var ax:int = 0; ax < assocList.length(); ax++) {
				var assoc:XML = assocList[ax];
				if (assoc && assoc.arg.(@key == 'name').@value == name) {
					var clsName:String = assoc.arg.(@key == 'className').@value;
					trace('clsName: ' + clsName);
					var klass:Class = flash.utils.getDefinitionByName(clsName) as Class;
					var aType:String = assoc.arg.(@key == 'type').@value;
					associations[name] = new Associator(this, klass, aType);
					return associations[name]; 
				}				
			} 
			
			return undefined;
		}
		
		override flash_proxy function setProperty(name:*, value:*):void {
			if (fieldValues.hasOwnProperty(name)) {
				fieldValues[name] = value;
				recChanged = true;
				fieldsChanged[name] = true;		
			} else {
				throw "Property Unknown"
			}			
		}
		
		override flash_proxy function callProperty(name:*, ...args):* {
			var matchSyntax:Array = name.toString().match(/^([a-z]+)(.+)/);
			
			return false;
		}
		
		public function get className():String {
			var name:String = flash.utils.getQualifiedClassName(this);
			var cp:Array = name.split('::');
			name = cp[cp.length - 1];			
			return name;			
		} 
		
		public function get unsaved():Boolean {
			return newRecord || recChanged;
		}

		/**
		 * Private Helpers and Operations Support
		 **/
		// construct sql from object parameters
		private function constructSql(query:Object):String {
			var sqs:String = "SELECT ";
			sqs += (query && query.select) ? query.select : "*"; 
			sqs += " FROM " + mStoreName;
			if (query && query.joins) {
				sqs += " " + query.joins + " ";
			}
			if (query && query.conditions) {
				sqs += " WHERE " + query.conditions;
			}
			if (query && query.group) {
				sqs += " GROUP BY " + query.group;
			}
			if (query && query.order) {
				sqs += " ORDER BY " + query.order;
			}
			if (query && query.limit) {
				sqs += " LIMIT " + query.limit;
			}			
			return sqs;
		}
				 
		// reset all fields (empty object)
		// Prior changes are discarded.
		protected function resetFields():void	{
			for (var key:String in fieldValues) {
				// only reset values, keep the keysfieldV
				fieldValues[key] = null;
			}
			resetState();
		}
		
		// reset the state - extreme - use with caution
		protected function resetState():void {
			newRecord = recLoaded = recChanged = false;
		} 

		
 		protected function timeStamp(field:String, values:Object=null):void {
			if (fieldValues.hasOwnProperty(field)) {
				if (values) {
					values[field] = new Date();
				} else {
					fieldValues[field] = new Date();
				}
			}
		}
	}
}