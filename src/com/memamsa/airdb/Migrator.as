package com.memamsa.airdb
{
	import flash.data.SQLColumnSchema;
	import flash.data.SQLConnection;
	import flash.data.SQLStatement;
	import flash.data.SQLTableSchema;	
	
	/** 
	*  The <code>Migrator</code> accepts schema information for a 
	*  <code>Modeler</code> sub-class and automatically migrates the
	*  database table and column definitions to reflect the schema specified 
	*  as part of the class definition.
	*  
	*  <p>Typically, each Modeler sub-class instantiates a Migrator object, 
	*  either as a Class constant or static member variable, with information 
	*  about its <code>Modeler</code> sub-class, table options and a set of 
	*  directives for column definitions.</p>
	*  
	*  <p>Additional directives can be added to the code at any time. When
	*  instantiated, each <code>Migrator</code> object compares the schema 
	*  information for their model using version numbers, and applies the 
	*  latest directives to bring the schema up-to-date.</p>
	*  
	*  <p>The <code>Migrator</code> provides several basic methods for defining
	*  columns and creating tables, including short-cut specifiers for foreign 
	*  key mapping and join table creation. Generally, migrations are non-
	*  destructive. This especially allows AIR applications to seamlessly
	*  update their schema as part of application updates while keeping user 
	*  data intact.</p>
	*  
	*  @example A model class for a blog Post that has defined schema over time
	*  in terms of three migration directives. 
	*  
	*  <listing version="3.0">
	*  dynamic class Post extends Modeler {
	*     private static var migrations:Migrator = new Migrator(
	*       // model class on which to apply the migration
	*       Post,
	*       // global options, id as primary autoincr field, 
	*       // name table as 'blog_posts' default would be 'posts'
	*       {id: true, storage: 'blog_posts'},
	*       // migration directives. 
	*       [
	*         function(my:Migrator):void {
	*           my.createTable(function():void{
	*             my.column('title', DB.Field.VarChar, {limit: 255});
	*             my.column('url', DB.Field.VarChar, {limit: 128});
	*             my.columnTimeStamps();
	*           });
	*         },
	*         function(my:Migrator):void {
	*           my.belongsTo(User)
	*         },
  *         function(my:Migrator):void {
  *           my.joinTable(Category);
  *         }
  *         // New directives go here
	*       ]
	*     )
	*  }
	*  </listing>
	*  
	*  @see Modeler
	*  @see DB
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
		private var mTableSchema:SQLTableSchema;
		// Columns that have already been added (read from table schema)
		// Used to check for existence of column
		private var mAddedColumns:Object;
		// Table did not exist and was therefore created
		private var created:Boolean = false;
    
    /**
    * @internal   
    * 
    * Note: The Migrator sets store name and field names for its
    * corresponding Modeler sub-class objects by setting the prototype members on
    * the model class.
    * 
    * Note: Migrations are non-destructive. We do not delete existing tables		
    **/
    
    /**
    * Construct a <code>Migrator</code> for a given model.
    * 
    * @param klass The <code>Modeler</code> sub-class whose schema to manage.
    * 
    * @param options An Object specifying global schema settings. 
    * <ul>
    * <li><strong>id</strong>: <code>Boolean</code>. If true, adds a PRIMARY 
    * AUTOINCREMENT column called id</li>
    * <li><strong>guid</strong>: <code>int</code>. Adds a VARCHAR column of 
    * specified length, named guid</li>
    * <li><strong>storage</strong>: <code>String</code>. Specifies an 
    * alternate name for the table associated with this model. By default,
    * the table name is constructed by inflecting the class name</li>
    * </ul>
    * 
    * @param directives A list of migration directives, each of which is a
    * function taking in a <code>Migrator</code> as a parameter and returning
    * <code>void</code>. Use methods on the <code>Migrator</code> object to 
    * specify schema.
    * <pre>
    *   function(my:Migrator):void {
    *   }
    * </pre>
    * @see DB#mapTable
    * @see Inflector
    * @see Modeler
    **/
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
			readTableSchema();
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
		* Returns the storeName (database table name) corresponding to this 
		* <code>Migrator</code>
		* 
		* @see IMigratable
		* 
		**/
		public function get storeName():String {
			return mStoreName;
		}

    /**
    * Runs necessary migration directives to bring the schema for the
    * corresponding database table up-to-date. The N migration directives
    * specified during instantiation of this <code>Migrator</code> are
    * considered as versions from 0 to N-1
    * 
    * @param fromVer Starting schema version for this table. 
    * @default 0
    * 
    * @param toVer Desired ending version for the schema. 
    * @default 0, in which case all directives upto the last are applied.
    * 
    * @return The final schema version after necessary migration directives
    * have been applied. 
    * 
  	* @see IMigratable
  	* @see DB#migrate
    * 
    **/
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
		
		/**
		* @internal Conveys schema information to the associated <code>Modeler</code> 
		* sub-class by adding the field name to the class prototype member.
		**/
		private function schemate():void {
			var tblSchema:SQLTableSchema = DB.getTableSchema(mStoreName);
			if (tblSchema && tblSchema.columns.length > 0) {
				for each (var col:SQLColumnSchema in tblSchema.columns) {
					addFieldToModeler(col.name);
				}
			}
		}
		
		// Add field to our modeler class objects by setting the fieldNames
		// array as a member of the class prototype
		private function addFieldToModeler(name:String):void {
			if (!mKlass.prototype.fieldNames) {
				mKlass.prototype.fieldNames = new Array();
			} 
			mKlass.prototype.fieldNames.push(name);			
		}
		
		// Returns true if there is a column named 'id' of type DB.Field.Serial
		// FIX: this method needs to be deprecated and proper use must be made
		// of ROWID.
		private function get hasAutoKeyId():Boolean {
			for (var idx:int = 0; idx < mFieldSet.length; idx++) {
				if (mFieldSet[idx][0] == 'id' && mFieldSet[idx][1] == DB.Field.Serial) {
					return true;
				}
			}
			return false;
		}
		
		/**
		* Column specifier. This method can be used either inside or outside of the
		* function block argument for createTable
		* 
		* @param name Field name for the database column. 
		* 
		* @param dataType The column type. 
		* 
		* @param options An object specifying column options or defaults. 
		* 
		* Here are the pre-defined constants for columns and supported options. 
		* <ul>
		* <li><code>DB.Serial</code> - PRIMARY AUTOINCREMENT</li>
		* <li><code>DB.Integer</code> - default</li>
		* <li><code>DB.VarChar</code> - limit, default</li>
		* <li><code>DB.DateTime</code></li>
		* <li><code>DB.Text</code></li>
		* <li><code>DB.Blob</code></li>
		* <li><code>DB.Float</code></li>                                                                                
		* </ul>
		* 
		* @see Migrator#createTable
		* 
		**/		
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
		private function addColumn(name:String, dataType:uint, options:Object):void {
			if (!existsColumn(name)) {
				stmt.text = "ALTER TABLE " + mStoreName + " ADD COLUMN " + 
				  DB.fieldMap([name, dataType, options]);
        /*trace('addColumn: ' + stmt.text);*/
				stmt.execute();
			}
		}	
		
		/**
		* Unsupported in SQLite
		**/
		public function removeColumn(name:String):void {
			// ALTER TABLE REMOVE COLUMN - unsupported in SQLite
		} 
		
		/**
		* Short-cut specifier to add created_at and updated_at DATETIME columns
		**/
		public function columnTimestamps():void {
			column('created_at', DB.Field.DateTime);
			column('updated_at', DB.Field.DateTime);
		}
		

		// Create table specifier.
		// Accepts a function block which is invoked BEFORE the actual create. 
		// Use the function block to specify table column schema using the 
		// Migrator.column method
		
		/** 
		* Create the database table corresponding to the model. 
		* Safely returns if table was already created or exists. 
		* 
		* @param block A function block which is executed before the actual 
		* creation of the table. This function block can include column definitions
		* which will be applied at once in one CREATE TABLE statement.
		* 
		**/		
		public function createTable(block:Function=null):void {
		  // If table has already been created, we return
			if (tableCreated) return;
			// Invoke schema function before we act on create
			if (typeof(block) == 'function') block.call();
			
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
		
		/**
		* Drop associated table from the database.
		* <strong>Caution</strong>: Data will be lost. Use appropriate judgement.
		**/
		// 
		public function dropTable():void {
		  if (!tableCreated) return;
		  stmt.text = "DROP TABLE IF EXISTS " + mStoreName;
		  stmt.execute();
		  created = false;
		  readTableSchema();
		}
		
		/**
		* Construct a join table for a has_and_belongs_to_many association.
		* The join table has two columns corresponding to the foreign_keys of 
		* each of the table in the association. The name for the join table is
		* conjugated from the table names being associated. 
		* 
		* @param klass The class for the other model to be associated with. 
		*
		* @param joinAttr (optional) Additional attributes for the join 
		* relationship. Specified as an array of fieldSpec arrays. 
		* 
		* @see Associator
		* @see DB#mapJoinTable
		* @see DB#mapForeignKey
		* @see Migrator#column
		* @see DB#fieldMap		
		**/
		public function joinTable(klass:Class, joinAttr:Array=null):void {
			var jtName:String = DB.mapJoinTable(mKlass, klass);
			var defs:Array = [
				DB.fieldMap([DB.mapForeignKey(mKlass), DB.Field.Integer]),
				DB.fieldMap([DB.mapForeignKey(klass), DB.Field.Integer])
			];
			if (joinAttr) {
				for each (var fspec:Array in joinAttr) {
					defs.push(DB.fieldMap(fspec));
				}
			}
			stmt.text = "CREATE TABLE IF NOT EXISTS " + jtName + 
				" (" + defs.join(',') + ")"; 
			stmt.execute();	
		}
		
		/**
		* Specify a foreign key column for another model within the table for this
		* model. 
		* 
		* @param klass The class for the other model (which has_many of this model)
		* 
		* @see Associator
		* @see DB#mapForeignKey
		**/
		public function belongsTo(klass:Class):void {
		  var bfName:String = DB.mapForeignKey(klass);
		  column(bfName, DB.Field.Integer, {'default': 0});
		}
		
	  private function readTableSchema():void {
	    mTableSchema = null;
	    mAddedColumns = new Object();
			mTableSchema = DB.getTableSchema(mStoreName);
			if (mTableSchema) {
				for each (var col:SQLColumnSchema in mTableSchema.columns) {
					mAddedColumns[col.name] = col;
				}				
			}
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

