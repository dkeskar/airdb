package com.memamsa.airdb
{
	import flash.data.SQLColumnSchema;
	import flash.data.SQLConnection;
	import flash.data.SQLStatement;
	import flash.data.SQLTableSchema;	
	
	/** 
	*  Migrator
	*  
	*  Allows migration directives to be specified and run as required.
	*  Typically, each Modeler sub-class instantiates a Migrator object, 
	*  either as a Class constant or static member. 
	*  
	*  Each Migrator object is initialized with information about its Model 
	*  class, table options and the set of column and table relationship 
	*  directives that constitute the schema for that Model.
	*  
	*  Upon DB initialization, each Migrator object is called upon to 
	*  migrate the schema from a starting version to latest. 
	*  
	**/
	
	public class Migrator implements IMigratable
	{
		private var mStoreName:String = null;		    // table name
		private var mKlass:Class = null;            // Model being migrated
		private var mOptions:Object = null;         // Global options
		private var mDirectives:Array = null;       // Schema directives
		private var mFieldSet:Array = null;         // Column name, type, options
		
		// Reuse the same SQLStatement and SQLConnection for efficiency
		private var stmt:SQLStatement = null;
		private var dbConn:SQLConnection = null;
		// Get and use the SQLTableSchema for column existence checks
		private var mTableSchema:SQLTableSchema = null;
		// Columns that have already been added (read from table schema)
		// Used to check for existence of column
		private var mAddedColumns:Object = new Object();
		// Table did not exist and was therefore created
		private var created:Boolean = false;

    // Migrator objects are typically instantiated from within Model classes.
    // Requires the model class name, global options and the array of schema
    // directives. 
    
    // Note: The Migrator sets store name and field names for the Model objects
    // by setting the prototype members for the Model class. 
		public function Migrator(klass:Class, options:Object, directives:Array)
		{
			mKlass = klass;
			mOptions = options; 
			mDirectives = directives;
			mFieldSet = [];

			stmt = new SQLStatement();
			dbConn = stmt.sqlConnection = DB.getConnection();
			
			// Set storename based on AirDB-style mapping of class name unless
			// custom name has been specified via the 'storage' property in options.
			if (options && options.hasOwnProperty('storage') && options['storage']) {
				mStoreName = options['storage'];
			} else {
			  mStoreName = DB.mapTable(mKlass);
			}
      // Set the store name property for our Model class objects. 
			mKlass.prototype.storeName = mStoreName; 
			// get table schema before processing column options
			mTableSchema = DB.getTableSchema(mStoreName);
			if (mTableSchema) {
				for each (var col:SQLColumnSchema in mTableSchema.columns) {
					mAddedColumns[col.name] = col;
				}				
			}
			// process column specifiers shortcuts
		  if (options && options.hasOwnProperty('id') && options['id']) {
				column('id', DB.Field.Serial);
			}
			if (options && options.hasOwnProperty('guid') && options.guid) {
			  column('guid', DB.Field.VarChar, {limit: options.guid});
			}
			// Register with the DB that we are ready to be migrated. 
			// The actual migration is invoked and carried out via our 
			// implementation of IMigratable.migrate
			DB.migrate(this);
			
			// Set field names for our model objects
			schemate();
		}
	
		/**
		 * IMigratable
		 **/
		public function get storeName():String {
			return mStoreName;
		}

		// run the necessary migrations and return the cumulative count
		public function migrate(fromVer:uint=0, toVer:uint = 0):uint {
			if (toVer == 0) {
			  // Migrate upto and including the final directive
				toVer = mDirectives.length;
			}
			try {
				for (var vx:uint = fromVer; vx < toVer; vx++) {
				  // call all necessary migration directives 
					mDirectives[vx].call(this, this);
				} 				
			} catch(error:Error) {
				trace("Migrator.migrate: ERROR applying directives\n" + error.message);
				toVer = 0;
			}
			return toVer;
		}
		
		// set all existing field names on our modeler class objects
		public function schemate():void {
			var tblSchema:SQLTableSchema = DB.getTableSchema(mStoreName);
			if (tblSchema && tblSchema.columns.length > 0) {
				for each (var col:SQLColumnSchema in tblSchema.columns) {
					addFieldToModeler(col.name);
				}
			}
		}
		
		// Add field to our modeler class objects by setting the fieldNames
		// array as a member of the class prototype
		public function addFieldToModeler(name:String):void {
			if (!mKlass.prototype.fieldNames) {
				mKlass.prototype.fieldNames = new Array();
			} 
			mKlass.prototype.fieldNames.push(name);			
		}
		
		// Returns true if there is a column named 'id' of type DB.Field.Serial
		// FIX: this method needs to be deprecated and proper use must be made
		// of ROWID.
		public function get hasAutoKeyId():Boolean {
			for (var idx:int = 0; idx < mFieldSet.length; idx++) {
				if (mFieldSet[idx][0] == 'id' && mFieldSet[idx][1] == DB.Field.Serial) {
					return true;
				}
			}
			return false;
		}
		
		// Migrator object method to specify a column schema. 
		// For use within a block call argument to createTable
		public function column(name:String, dataType:uint, options:Object = null):void {
		  // If table has not been created, store this schema information in the 
		  // fieldset array to allow combining into one CREATE TABLE statement.		  
		  if (!tableCreated) {
		    mFieldSet.push([name, dataType, options]);  
		  } else {
		    // Table exists, alter table to add this column
		    addColumn(name, dataType, options);
		  }			
		}
		
		// Alter existing table to add a new column
		public function addColumn(name:String, dataType:uint, options:Object):void {
			if (!existsColumn(name)) {
				stmt.text = "ALTER TABLE " + mStoreName + " ADD COLUMN " + 
				  DB.fieldMap([name, dataType, options]);
        /*trace('addColumn: ' + stmt.text);*/
				stmt.execute();
			}
		}	
			
		public function removeColumn(name:String):void {
			// ALTER TABLE REMOVE COLUMN - unsupported in SQLite
		} 
		
		// Short-cut specifier to add created_at and updated_at DATETIME columns
		public function columnTimestamps():void {
			column('created_at', DB.Field.DateTime);
			column('updated_at', DB.Field.DateTime);
		}
		
		// Create table specifier.
		// Accepts a function block which is invoked BEFORE the actual create. 
		// Use the function block to specify table column schema using the 
		// Migrator.column method
		
		// Note: Migrations are non-destructive. We do not delete existing tables
		public function createTable(block:Function):void {
		  // If table has already been created, we return
			if (tableCreated) return;
			// Invoke schema function before we act on create
			block.call();
			
			var defs:Array = [];
			// mFieldSet is populated by Migrator.column, typically in the block
			// argument provided to createTable. 
			for (var ix:uint = 0; ix < mFieldSet.length; ix++) {
        /*trace("ix: " + ix + " : " + mFieldSet[ix].toString());*/
				defs.push(DB.fieldMap(mFieldSet[ix]));
			}
			stmt.text = "CREATE TABLE IF NOT EXISTS " + mStoreName + 
				" (" + defs.join(',') + ")";
			
			stmt.execute();
			created = true;
		}
		
		// Join table directive. 
		// Using this our Modeler class can specify construction of a join table
		// to store relationship with another Model
		public function joinTable(klass:Class):void {
			var jtName:String = DB.mapJoinTable(mKlass, klass);
			var defs:Array = [
				DB.fieldMap([DB.mapForeignKey(mKlass), DB.Field.Integer]),
				DB.fieldMap([DB.mapForeignKey(klass), DB.Field.Integer])
			];
			stmt.text = "CREATE TABLE IF NOT EXISTS " + jtName + 
				" (" + defs.join(',') + ")"; 
			stmt.execute();	
		}
		
		// Using the belongsTo directive, our Modeler class can specify the 
		// inclusion of a foreign_key for another Model within this table. 
		public function belongsTo(klass:Class):void {
		  var bfName:String = DB.mapForeignKey(klass);
		  column(bfName, DB.Field.Integer, {'default': 0});
		}
	
	  // Returns true if the table was just created or if it already exists
	  private function get tableCreated():Boolean {
	  	return (created || mTableSchema);
	  }
	  
	  // Checks for the existence of a column.
	  private function existsColumn(name:String):Boolean {
	  	return (mAddedColumns[name] ? true : false);
	  }	
	  
	  // Unused.
	  private function matchesColumn(name:String, dataType:uint, options:Object):Boolean {
	  	// modify column not yet supported.
	  	return false;
	  }  
	}
}

