package com.memamsa.airdb
{
	/**
	 * Modeler
	 * Provides base class functionality for Object Relational Modeling of 
	 * database tables. Sub-classes of Modeler (models) are automatically
	 * mapped to database tables, and support data manipulation and query methods
	 * such as load, create, update, delete, save and findAll.
	 * 
	 * The actual schema for the model table is independent of the Modeler. 
	 * AirDB provides the Migrator class to allow models to dynamically evolve and
	 * migrate their schema. The Modeler uses the schema information for checking
	 * field names and optimizing certain operations. 
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
	  /**
	  *  Note: Migrator puts following on the Modeler class prototype
	  *  fieldNames - An Array of field names 
	  *  storeName - the DB table associated with this Model.
	  **/
		 
		// The field values found, updated, created or deleted
		private var recNew:Boolean;           // newly initialized fields
		private var recLoaded:Boolean;        // fields loaded from DB
		private var recChanged:Boolean;       // fields have been changed
		private var recDeleted:Boolean;       // delete operation carried out
		// The actual fields that changed. 
		// Used for efficiently saving or updating the record
		private var fieldsChanged:Object = {};
		private var mStoreName:String = null; // our table name
		private var stmt:SQLStatement = null;
		
		// sub-class(es) can access fieldValues directly (if they need to) 
		protected var fieldValues:Object = new Object();
		
		// associations
		private var associations:Object = {};

		public static const PER_PAGE_LIMIT:int = 50;      // query pagination default
				
		public function Modeler()
		{
		  // create SQLStatement and SQLConnection for efficient reuse.
			stmt = new SQLStatement();
			stmt.sqlConnection = DB.getConnection();

      // Get our storename and field values from the class prototype 
      // information set by the Migrator.
			var fqName:String = flash.utils.getQualifiedClassName(this);
			var model:Class = flash.utils.getDefinitionByName(fqName) as Class;
			mStoreName = model.prototype.storeName; 
			for each (var fname:* in model.prototype.fieldNames) {
				fieldValues[fname] = null;
			}
			// set this to be a newly initialized object. 
			// this allows new ModelClass() to be used for creating new record
			recNew = true;
		}
		
		// Static method to find and load data into an instance of a 
		// Modeler sub-class. Used to get a particular model object based
		// on some conditions. 
		// e.g. if Post extends Modeler
		// var post:Post = Modeler.findery(Post, {author: 'dude'});
		//
		public static function findery(klass:Class, keyvals:Object):Modeler {
		  var obj:Modeler = new klass;
		  if (!obj.load(keyvals)) return null;
		  return obj;
		}
		
		// initialize this object to hold fields for a new record. 
		public function data(values:Object):void {
			if (!values) return;
			resetFields();			
			
			for (var key:String in values) {
				if (fieldValues.hasOwnProperty(key)) {
					fieldValues[key] = values[key];
				} else {
					throw new Error(mStoreName + ': Field Unknown:' + key);
				}
			}
			// TODO: add check if primary id is being set
			recNew = true;
		}

		// save newly initialized or modified data
		public function save():Boolean {
		  if (recDeleted) {
		    throw new Error("Can't modify or save deleted data");
		  }
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
					throw new Error(mStoreName + ": Field Unknown: " + key);
				}
				clause += key + ' = ' + DB.sqlMap(keyvals[key]);
				conditions.push(clause);
			}
			stmt.text += conditions.join(' AND ');
			try {
				stmt.execute();
				var result:SQLResult = stmt.getResult();
				if (!result || !result.data) {
					return false;
				}
				if (result.data.length > 0) {
					// we trust the DB schema so whole new assignment is ok.
					fieldValues = result.data[0];
					recNew = false;
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
		public function findAll(query: Object, page:int=1, perPage:int=0):Array {
			resetFields();
			stmt.text = constructSql(query, page, perPage);
			try {
				stmt.execute();
				var result:SQLResult = stmt.getResult();
				if (!result || !result.data) {
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
				throw new Error(mStoreName + '.count: cannot interpret result'); 
			} catch (error:SQLError) {
				trace("ERROR: count: " + error.details);
			}
			return -1;
		}
		
		// Count the number of reqcords which match query criteria 
		// The query object accepts the following keys corresponding to SQL clauses.
		// -> conditions, group, order, limit, joins
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

		// create a record with given values
		// The given values, where specified, override the field values stored 
		// currently in the Modeler object fieldValues. 
		public function create(values:Object=null):Boolean {
		  if (recDeleted) {
		    throw new Error("Can't modify or save deleted data");
		  }
			if (!values && !newRecord) return false;
			var key:String;
			if (!values && newRecord) {
				values = fieldValues;
			}
			// Apply specified values to ensure all fieldValues are the latest.
			for (key in values) {
				if (!fieldValues.hasOwnProperty(key)) {
					trace('create: unknown fields specified');
					throw new Error(mStoreName + ".create: Field Unknown: " + key);
				}
				if (values[key] == null) continue;
				fieldValues[key] = values[key];
			}
			// Invoke overridable before-hook methods.
			// The before hooks may change fields and act using latest values
			beforeCreate();
			beforeSave();
			if (!validateData()) return false; 
			timeStamp('created_at');
			
			var cols:Array = [];
			var vals:Array = [];
			for (key in fieldValues) {
				if (!fieldValues[key]) continue;
			  cols.push(key);
  			vals.push(DB.sqlMap(fieldValues[key]));  			  
			}

			stmt.text = "INSERT INTO " + mStoreName;			
			stmt.text += " (" + cols.join(',') + ")";
			stmt.text += " VALUES (" + vals.join(',') + ")";
			try {
				stmt.execute();
				var result:SQLResult = stmt.getResult();
				if (result && result.complete) {
					fieldValues['id'] = result.lastInsertRowID;
    			recLoaded = true;					
				}
			} catch (error:SQLError) {
				trace("ERROR: create: " + error.details);
				return false;
			}
			recNew = recChanged = false;
			return true;
		}
		
		// Update the database record for the currently loaded object to 
		// reflect any changed values, including those specified as parameters 
		// to this method.
		public function update(values:Object=null):Boolean {
		  if (recDeleted) {
		    throw new Error("Can't modify or save deleted data"); 
		  }
			if (!values && !recChanged) return false;
			// new records should be "created"
			if (!values && newRecord) {
			  throw new Error(mStoreName + ".update: Expected create");
		  }

			var assigns:Array = [];
			var key:String;
			var changed:Boolean = recChanged;
			
			// Apply specified values to ensure all fieldValues are latest
			for (key in values) {
				if (!fieldValues.hasOwnProperty(key)) {
					trace('update: unknown field: ' + key);
					throw new Error(mStoreName + '.update: Field Unknown: ' + key);
				}
				// Assumption: If there exists an 'id' field for this model, 
				// then the id field value CANNOT be modified directly in update. 
				// We simply ignore attempts to set the 'id' field value.
				if (values[key] && fieldValues[key] != values[key] && key != 'id') {
					fieldValues[key] = values[key];
					// Note down field names that have changed (for efficient update)
					changed = true;
					fieldsChanged[key] = true;
				}
			}
			// Invoke overridable before-update, before-save and validateData hooks.
			// These hooks get to perform validation or computation using the latest
			// values which we set above.
			beforeUpdate();
			beforeSave();			
			if (!validateData()) return false;
			
			// Carry out the DB UPDATE if things actually have changed
			if (changed) {
				for (key in fieldsChanged) {
					assigns.push(key + " = " + DB.sqlMap(fieldValues[key]));
				}
				stmt.text = "UPDATE " + mStoreName + " SET ";
				stmt.text += assigns.join(',');
				
				// Assumption: we use the 'id' field to ensure that this specific
				// record is updated. If there is not an 'id' field for the model, 
				// the UPDATE will apply to all records. 
				// The ID is either from the fieldValues previously populated with a 
				// load() or by using the id key in the values passed to this method. 
				if (recLoaded || (values && values.hasOwnProperty('id'))) {
					stmt.text += " WHERE id = " + 
					        ((values && values['id']) || fieldValues['id']).toString(); 
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
		// Use SQL-style condition and update clauses. 
		// e.g. updateAll("some <> XY AND foo LIKE '%nice%'", "bar = 'value'")
		public function updateAll(conditions:String, values:Object):uint {
			resetFields();
			stmt.text = "UPDATE " + mStoreName + " SET ";
			var assigns:Array = [];
			for (var key:String in values) {
				if (!fieldValues.hasOwnProperty(key)) {
					trace('update: unknown field: ' + key);
					throw new Error(mStoreName + '.updateAll: Field Unknown: ' + key);
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
		
		// Delete this record
		public function remove():Boolean {
		  // If there is no id field for this table, we have no basis to remove.
		  // It is assumed that the object has been loaded with the record we 
		  // wish to delete.
		  if (!fieldValues.id) return false;
		  stmt.text = "DELETE FROM " + mStoreName + 
		          ' WHERE (id IN (' + fieldValues.id + '))';
		  try {
		    stmt.execute();
		    var result:SQLResult = stmt.getResult();
		    if (!result || !result.data) {
		      trace('DELETE failed');
		      return false;
		    }
		  } catch (error:SQLError) {
		    trace('ERROR:delete: '  + error.details);
		    return false;
		  }
		  recDeleted = true;
		  return true;
		}
		
		/**
		* Overridable functions for validation and automatic actions 
		**/
		// called when Modeler.save() called, whether new or existing
		protected function beforeSave():void {}
		// called before INSERT for new records
		protected function beforeCreate():void {}
		// called before UPDATE (and after beforeSave)
		protected function beforeUpdate():void {}
		// Called before save or create. If false, aborts DB operation
		protected function validateData():Boolean {return true;}
		
		/** 
		 * Property Overrides to handle column names and associations 
		 **/
		override flash_proxy function hasProperty(name:*):Boolean {
			// TODO: also check associations meta-data
			return fieldValues.hasOwnProperty(name);
		} 
		
		// Returns the value or the association for the given property name
		override flash_proxy function getProperty(name:*):* {
			name = name.toString();
			if (name == 'storeName') return mStoreName;
						
			if (fieldValues.hasOwnProperty(name)) {
			  // this property is part of the known schema, return the fieldvalue.
				return fieldValues[name];
			}
			if (name in associations) {
			  // if we have previously cached the Associator object corresponding 
			  // to this property, return the cached object
				return associations[name];
			}
			
			// look through the association meta-data to see if we support this
			// named association as a property. 
			var assocList:XMLList = Reflector.getMetadata(this, "Association");
			for (var ax:int = 0; ax < assocList.length(); ax++) {
				var assoc:XML = assocList[ax];
				if (assoc && assoc.arg.(@key == 'name').@value == name) {
				  // Found a property with the given name as an association specified
				  // with that name. Get the corresponding class name that it maps to.
					var clsName:String = assoc.arg.(@key == 'className').@value;
          /*trace('clsName: ' + clsName);*/
          
          // Construct a new Associator to handle the querying and mapping.
          // The associator needs the class and the relationship type as 
          // specified in the meta-data. 
					var klass:Class = flash.utils.getDefinitionByName(clsName) as Class;
					var aType:String = assoc.arg.(@key == 'type').@value;
					
					// create and cache the associator for future use.  
					associations[name] = new Associator(this, klass, aType);
					return associations[name]; 
				}				
			} 
			
			return undefined;
		}
		
		override flash_proxy function setProperty(name:*, value:*):void {
		  if (recDeleted) {
		    throw new Error("Can't modify or save deleted data"); 
		  }
			if (fieldValues.hasOwnProperty(name)) {
				fieldValues[name] = value;
				recChanged = true;
				fieldsChanged[name] = true;		
			} else {
				throw new Error("Unknown Property: " + name);
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
			return (recNew || recChanged);
		}

		/**
		 * Private Helpers and Operations Support
		 **/
		// construct sql from object parameters
		private function constructSql(query:Object, page:int=1, perPage:int=0):String {
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
			var lim:int = 0;
			if (query && query.limit) {
			  lim = query.limit;
		  } else if (perPage > 0) {
		    lim = perPage;
		  }
		  if (lim > 0) {
		    sqs += " LIMIT " + lim;
  			if (page > 1 && perPage > 0)	{
  			  sqs += " OFFSET " + (page - 1)*perPage;
  			}		    
		  }			
			return sqs;
		}
		
		public function get newRecord():Boolean {
		  return (recNew || !fieldValues['id']);
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
			recNew = recLoaded = recChanged = recDeleted = false;
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