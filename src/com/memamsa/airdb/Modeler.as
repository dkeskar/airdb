package com.memamsa.airdb
{
	import flash.data.SQLResult;
	import flash.data.SQLStatement;
	import flash.errors.SQLError;
	import flash.utils.Proxy;
	import flash.utils.flash_proxy;
	import flash.utils.getDefinitionByName;
	import flash.utils.getQualifiedClassName;
  
	/**
	 * The <code>Modeler</code> provides base class functionality for Object 
	 * Relational Modeling of database tables, fields and operations. Sub-classes
	 * of <code>Modeler</code> (models) are automatically mapped to tables, and 
	 * include support for data manipulation and query methods such as load, 
	 * create, update, delete, save and findAll.
	 * 
	 * <p>The actual schema for the model table is specified within the Modeler
	 * sub-class, using a composite member instance of the <code>Migrator</code> 
	 * class. This schema information is used for checking field names and 
	 * optimizing certain operations.</p>
	 * 
	 * <p>The model can also define associations with other models. Associations 
	 * help map table relationships in the database schema (such as many-many, 
	 * one-many, etc) in terms of model objects and provide a quick and in some 
	 * cases automated mechanism for querying and finding the associated table 
	 * records. 
	 * 
	 * @example A model to represent a blog Post, each of which has many Comments
	 * <listing version="3.0">
	 * [Association(type="has_many", name="comments", className="example.model.Comment")]
	 * [Association(type="belongs_to", name="author", className="example.model.Person")]
	 * dynamic class Post extends Modeler
	 * {
	 *    private static var schema_migrations:Migrator = new Migrator(
	 *      Post, 
	 *      {id: true},
	 *      [
	 *        function(my:Migrator):void {
	 *          my.belongsTo(Person);
	 *          my.createTable(function():void {
	 *            my.column('title', DB.Field.VarChar, {limit: 255});
	 *            my.columnTimeStamps();
	 *          });
	 *        }
	 *      ]
	 *    );
	 *    // other class members and methods
	 * } 
	 * </listing>
	 * 
	 * @see com.memamsa.airdb.Migrator
	 * @see com.memamsa.airdb.Associator
	 **/	
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
			fieldValues['_rowid'] = null;
			// set this to be a newly initialized object. 
			// this allows new ModelClass() to be used for creating new record
			recNew = true;
		}
		
		/**
		* Create an instance of the specified <code>Modeler</code> sub-class and 
		* load it with the record information matching given key values. 
		* 
		* @param klass The classname, which should be a sub class of 
		* <code>Modeler</code>
		* 
		* @param keyvals An Object where the keys correspond to field names and 
		* values specify the condition to be matched against that field. 
		* 
		* @example Find blog Posts by a particular author
		* <listing version="3.0">
		* var author:Person = Modeler.findery(Person, {name: 'Cool Dude'});
		* var post:Post = Modeler.findery(Post, {author_id: author.id});
		* </listing>
		* 
		* @return If there exists a record matching the conditions specified in 
		* the <code>keyvals</code>, returns an instance of the specified 
		* <code>Modeler</code> sub-class loaded with the record information. 
		* Otherwise, returns null.
		**/
		public static function findery(klass:Class, keyvals:Object):Modeler {
		  var obj:Modeler = new klass;
		  if (!obj.load(keyvals)) return null;
		  return obj;
		}
		
		/**
		* Initialize this instance with specified field values, potentially for a 
		* new record. Any existing field information in this instance is reset.
		* 
		* @param keyvals An Object where the keys correspond to field names and 
		* the values to be assigned to them.
		**/
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

    /**
    * Save the field values in this instance to the database record. 
    * Creates a new record or updates an existing record appropriately based
    * on how this instance was loaded or initialized. 
    * 
    * @return <code>true</code> on successful save, <code>false</code> otherwise.
    **/
		public function save():Boolean {
		  if (recDeleted) {
		    throw new Error("Can't modify or save deleted data");
		  }
			if (!newRecord && !recChanged) return false;
			return (newRecord ? create() : update());
		}

    /**
    * Load this instance with record information matching specified conditions.
    * 
    * @param keyvals The conditions, expressed in terms of keys representing 
    * field names and their associated values to be matched. 
    * 
    * @return <code>true</code> if a matching record was found, otherwise 
    * <code>false</code>.
    **/
		public function load(keyvals:Object):Boolean {
			resetFields();
			if (!keyvals) return false;
				
			var conditions:Array = [];
			stmt.text = "SELECT ROWID as _rowid, * FROM " + mStoreName + " WHERE ";
			for (var key:String in keyvals) {
				var clause:String = "";
				if (!fieldValues.hasOwnProperty(key)) {
					throw new Error(mStoreName + ": Field Unknown: " + key);
				}
				clause += key + ' = :' + key;
				stmt.parameters[":" + key] = keyvals[key];
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
			} finally {
				stmt.clearParameters();
			}
			return true;
		}
		
		/**
		* Reload this previously loaded instance to obtain latest field values. 
		* All unsaved changes are lost. 
		* @return <code>true</code> if reload was successful, <code>false</code>
		* otherwise.
		**/
		public function reload():Boolean {
		  if (!fieldValues.hasOwnProperty('_rowid') || 
		      !fieldValues['_rowid']) return false;
		  return load({_rowid: fieldValues['_rowid']});
		}
		
		/**
		* Check for the existence of records matching criteria specified in terms 
		* of field names and associated values. This method <strong>will not change
		* </strong> the current object state or field values. 
		* 
    * @param keyvals The conditions, expressed in terms of keys representing 
    * field names and their associated values to be matched. 
    * 
    * @return <code>true</code> if matching records were found, otherwise 
    * <code>false</code>.
    * 
    * @see Modeler#findAll
    * @see Modeler#load
		**/
		public function find(keyvals:Object):Boolean {
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
			if (conditions.length <= 0) return false;			
			stmt.text += conditions.join(' AND ');
			try {
				stmt.execute();
				var result:SQLResult = stmt.getResult();
				if (!result || !result.data) {
					return false;
				}
				if (result.data.length > 0) {
				  return true;
				}
			} catch (error:SQLError) {
				trace("ERROR: find: " + error.details);
				return false;
			}
		  return false;
		}
		
		/**
		* A generic sql-based find method to query and load field information for 
		* all records based on SQL conditions, ordering and limits including join 
		* and grouping operations. 
		* 
		* @param query An Object whose keys can map to values corresponding 
		* to the following supported SQL clauses: 
		* <ul>
		* <li>select: fields and sub-selects, e.g. *, field as something, etc.</li>
		* <li>conditions: SQL conditions including AND, OR, etc.</li>
		* <li>group: field names that follow a GROUP BY</li>
		* <li>order: describe sorting as in ORDER BY, e.g. "name ASC"</li>
		* <li>limit: LIMIT clause, e.g. 10</li>
		* <li>joins: table join claues, e.g. inner join table on ...</li>
		* </ul>
		* 
		* @param page Specify record offset in terms of integer valued pages. 
		* @default 1
		* 
		* @param perPage The number of records to fetch per page
		* 
		* @return List of Objects representing the query result. 
		**/
		public function findAll(query: Object, page:int=1, perPage:int=0):Array {
			resetFields();
			stmt.text = constructSql(query, page, perPage);
			try {
				stmt.execute();
				var result:SQLResult = stmt.getResult();
				if (!result || !result.data) {
					return [];
				}
				
				return convertObjectsToThisType(result.data);
			} catch (error:SQLError) {
				trace('ERROR:findall: ' + error.details);
			}
			return [];	
		}
		
		/**
		* Count the total number of records in the table for this model.
		* 
		* @return The total record count
		* @see Modeler#countAll
		**/
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
		
		/**
		* Count the number of records matching specified query criteria
		* 
		* @param query An Object whose keys can map to values corresponding 
		* to the following supported SQL clauses: 
		* <ul>
		* <li>conditions: SQL conditions including AND, OR, etc.</li>
		* <li>group: field names that follow a GROUP BY</li>
		* <li>order: describe sorting as in ORDER BY, e.g. "name ASC"</li>
		* <li>limit: LIMIT clause, e.g. 10</li>
		* <li>joins: table join claues, e.g. inner join table on ...</li>
		* </ul>
		*
		* @return The count of records matching the query 
		* @see Modeler#count
		**/
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

    /**
    * Create a new record by combining field values in this instance with 
    * the specified values. 
    * 
    * @param keyvals An object containing field names as keys and corresponding
    * field values. These given values override the field values previously 
    * stored in the instance. 
    * 
    * @return <code>true</code> if new record was successfully created, 
    * <code>false</code> otherwise. 
    * 
    * @example Create the record for a new blog post
    * <listing version="3.0">
    * var post:Post = new Post();
    * post.title = "A new beginning";
    * post.author_id = 3;
    * post.create();
    * 
    * // Create another post by the same author
    * post.create({title: "A continuing saga"});
    * </listing>
    * 
    **/
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
  			    stmt.parameters[":" + key] = values[key];
			}
			
			stmt.text = "INSERT INTO " + mStoreName;			
			stmt.text += " (" + cols.join(',') + ")";
			stmt.text += " VALUES (:" + cols.join(',:') + ")";
			try {
				stmt.execute();
				var result:SQLResult = stmt.getResult();
				if (result && result.complete) {
					fieldValues['_rowid'] = result.lastInsertRowID;
					if (fieldValues.hasOwnProperty('id')) {
					  fieldValues['id'] = fieldValues['_rowid'];
					}
    			recLoaded = true;					
				}
			} catch (error:SQLError) {
				trace("ERROR: create: " + error.details);
				return false;
			} finally {
				stmt.clearParameters();
			}
			recNew = recChanged = false;
			return true;
		}
		
		/**
		* Update the database record currently loaded into the model object. 
		* Only updates changed fields or those for which new values are provided.
		* 
		* @param keyvals An object containing field names as keys and corresponding
		* field values. These given values override the field values previously 
		* stored in the instance. 
		* 
		* @return <code>true</code> if record was successfully updated, 
		* <code>false</code> otherwise. 
		* 
		* @see Modeler#save
		* @see Modeler#updateAll
		* @see Modeler#create
		* 
		* @example Update a person's karma score
		* <listing version="3.0">
		* var user:Person = Modeler.findery(Person, {id: 7});
		* user.update({karma: user.karma + 20});
		* </listing>
		**/
		// TODO: Fix this method to ensure it cannot accidentally UPDATE everything. 
		// This means, if rec is not loaded, it cannot be updated. 
		// Use updateAll when updating all records. 
		public function update(values:Object=null):Boolean {
		  if (recDeleted) {
		    throw new Error("Can't modify or save deleted data"); 
		  }
			if (!values && !recChanged) return false;
			// new records should be "created"
			if (!values && newRecord) {
			  throw new Error(mStoreName + ".update: Expected create");
		  }
		  // records must be loaded before they can be updated
		  if (!(fieldValues.hasOwnProperty('_rowid') && fieldValues['_rowid'])) {
		    throw new Error(mStoreName + ".update: No record loaded");
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
				// UNENFORCED: If there exists an 'id' field for this model, 
				// then the id field value should not be modified directly in update. 
				// We DO NOT prevent setting or modifying the 'id' field value.
				
				if (values[key] && fieldValues[key] != values[key]) {
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
					assigns.push(key + " = :" + key);
					stmt.parameters[":" + key] = fieldValues[key];
				}
				stmt.text = "UPDATE " + mStoreName + " SET ";
				stmt.text += assigns.join(',');
				
				// We use the SQLite ROWID integer key to ensure that this specific
				// record (previosly loaded) is the one that is updated. 
				stmt.text += " WHERE ROWID = " + fieldValues['_rowid'];
				try {
					stmt.execute();
				} catch (error:SQLError) {
					trace(stmt.text + "\nError: Update: " + error.details);
					return false;
				} finally {
					stmt.clearParameters();
				}
				// upon successful update, reflect new values in this object
				recChanged = false;
				fieldsChanged = {};
			}
			return true;
		}
		
		/**
		* Update all records matching specified conditions with new values
		* 
		* @param conditions A set of conditions in valid SQL syntax
		* 
		* @param keyvals An Object with keys representing field names and the
		* associated values as updated values. 
		* 
		* @return A count of the number of rows that were updated
		* 
		* @see Modeler#update
		* 
		* @example Add keyword string to all posts about SQLite
		* <listing version="3.0">
		* var post:Post = new Post();
		* post.updateAll("title like '%sql%'", {keywords: "sql,database"});
		* </listing>
		**/
		public function updateAll(conditions:String, values:Object):uint {
			resetFields();
			var assigns:Array = [];
			for (var key:String in values) {
				if (!fieldValues.hasOwnProperty(key)) {
					trace('update: unknown field: ' + key);
					throw new Error(mStoreName + '.updateAll: Field Unknown: ' + key);
				}
				assigns.push(key + ' = :' + key);
				stmt.parameters[':' + key] = values[key];
			}
			stmt.text = "UPDATE " + mStoreName + " SET ";			
			stmt.text += assigns.join(',');
			if (conditions) {
				stmt.text += " WHERE " + conditions;
			}
			try {
				stmt.execute();
				var result:SQLResult = stmt.getResult();
				if (!result || !result.rowsAffected) {
					trace('updateAll: update failed');
					return 0;
				}
				return result.rowsAffected;				
			} catch (error:SQLError) {
				trace('Error: updateAll: ' + error.details);
				return 0;
			}	finally {
				stmt.clearParameters();
			}
			return 0;
		}
		
		/**
		* Deletes the record represented by this object. The model object must
		* have previously been "loaded" with a record. 
		* 
		* @return <code>true</code> if record was successfully deleted, 
		* <code>false</code> otherwise. 
		* 
		**/
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
		    if (!result || !result.complete || result.rowsAffected != 1) {
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
		* Overridable method called before saving a newly created or updated reord. 
		* @see Modeler#save
		* @see Modeler#beforeCreate
		* @see Modeler#beforeUpdate
		**/		
		protected function beforeSave():void {}

		/**
		* Overridable method called before inserting new records. 
		* @see Modeler#save
		* @see Modeler#beforeSave
		* @see Modeler#beforeUpdate
		**/		
		protected function beforeCreate():void {}

		/**
		* Overridable method called before update of existing records. Invoked
		* <strong>after</strong> the <code>beforeSave()</code> callback. 
		* @see Modeler#save
		* @see Modeler#beforeSave
		* @see Modeler#beforeCreate
		**/		
		protected function beforeUpdate():void {}

		/**
		* Overridable method called before save or create to allow validation of 
		* field data. Set the return value to control whether to abort or proceed
		* with the save or create operation. 
		*  
		* @return Upon <code>false</code> result, the triggering save or create is
		* aborted. Return <code>true</code> to allow processing of valid data. 
		* @see Modeler#save
		* @see Modeler#beforeSave
		* @see Modeler#beforeCreate
		**/		
		protected function validateData():Boolean {return true;}
		
		/** 
		 * @internal Property Overrides to handle column names and associations 
		 **/
		override flash_proxy function hasProperty(name:*):Boolean {
			var hasProperty:Boolean = fieldValues.hasOwnProperty(name);
			if (!hasProperty) {
				var associator:Associator = findAssociation(name);
				if (associator) {
					hasProperty = true;
				}
			}

			return hasProperty;
		} 
		
		/**
		* @internal Returns the value or the association for the given property name
		**/
		override flash_proxy function getProperty(name:*):* {
			name = name.toString();
			if (name == 'storeName') return mStoreName;
						
			if (fieldValues.hasOwnProperty(name)) {
			  // this property is part of the known schema, return the fieldvalue.
				return fieldValues[name];
			}
			return findAssociation(name);			
		}
		
		private function findAssociation(name:String):Associator {
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

		/**
		* @internal
		**/
		override flash_proxy function setProperty(name:*, value:*):void {
		  if (recDeleted) {
		    throw new Error("Can't modify or save deleted data"); 
		  }
			if (fieldValues.hasOwnProperty(name)) {
				fieldValues[name] = value;
				recChanged = true;
				fieldsChanged[name] = true;		
			} else {
			  var assoc:Associator = findAssociation(name);
			  if (assoc) {
			    assoc.target = value;
			  } else {
  				throw new Error("Unknown Property: " + name);			    
			  }			  
			}			
		}
		
		/**
		* @internal
		**/
		override flash_proxy function callProperty(name:*, ...args):* {
			var matchSyntax:Array = name.toString().match(/^([a-z]+)(.+)/);
			
			return false;
		}
		
		/**
		* Returns the unqualified class name for the model. 
		* @return The model name, suitable for mapping to tables.
		**/
		public function get className():String {
			var name:String = flash.utils.getQualifiedClassName(this);
			var cp:Array = name.split('::');
			name = cp[cp.length - 1];			
			return name;			
		} 
		
		/**
		* Check if object has unsaved changes
		* @return <code>true</code> if new or changed record information
		**/
		public function get unsaved():Boolean {
			return (recNew || recChanged);
		}
    
		/**
		* Check if this object fields represent a new record
		* @return <code>true</code> if this is a new record
		**/
		public function get newRecord():Boolean {
		  return (recNew || !fieldValues['_rowid']);
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
					 
		// reset all fields (empty object)
		// Prior changes are discarded.
		protected function resetFields():void	{
			for (var key:String in fieldValues) {
				// only reset values, keep the keysfieldV
				fieldValues[key] = null;
			}
			resetState();
			resetAssociations();
		}
		
		// reset the state - extreme - use with caution
		protected function resetState():void {
			recNew = recLoaded = recChanged = recDeleted = false;
		} 
		
		// reset all associations
		protected function resetAssociations():void {
		  associations = {}
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
		
		private function convertObjectsToThisType(objects:Array):Array {
			var thisTypeArray:Array = new Array();
			var klass:Class;
			try {
				klass = flash.utils.getDefinitionByName(getQualifiedClassName(this)) as Class;
			} catch (error:Error) {
				klass = flash.utils.getDefinitionByName("com.memamsa.airdb.Modeler") as Class;
			}
			for each (var object:Object in objects) {
				var thisTypeObject:Object = new klass;
				for (var propertyName:String in object) {
					try {
						thisTypeObject[propertyName] = object[propertyName];
					// ignore errors, not all properties can be set.
					} catch (error:Error) {}
				}
				thisTypeArray.push(thisTypeObject);
			}
			
			return thisTypeArray;
		}
	}
}