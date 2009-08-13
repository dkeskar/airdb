package com.memamsa.airdb
{
	import flash.data.SQLConnection;
	import flash.data.SQLMode;
	import flash.data.SQLSchemaResult;
	import flash.data.SQLTableSchema;
	import flash.errors.SQLError;
	import flash.events.SQLEvent;
	import flash.filesystem.File;
	import flash.utils.getQualifiedClassName;
	
	/**
	*  DB constants, helpers and utilities. 
	*  
	*  <p>Use DB.initDB in your application startup code to name and initialize
	*  the database file.</p>
	*  
	*  <p>Use <code>Modeler</code> sub-classes as Object Relational Models with
	*  base-class supported create, update, delete and query operations. </p>
	*  
	*  <p>Use a <code>Migrator</code> member within your models for schema 
	*  definition, and migrations. </p>
	*  
	*  <p>Specify associations as class meta-data and add appropriate schema 
	*  support to get object relationships through the <code>Associator</code>.</p>
	*  
	*  @see Modeler
	*  @see Migrator
	*  @see Associator
	*  
	**/
	public class DB
	{
	  // This class is an unenforced singleton, providing only _static_ methods.
  	
		// Enumerations for Stored Data Types 
		public static const Field:Object = {
			Serial: 1, Integer: 2, VarChar: 3, DateTime: 4, Text: 5, Blob: 6, Float: 7
		}
		
		// The database name 
		// Assumption: The application uses only one database. 
		// All models in the application are stored in the single database. 
		private static var defaultDB:String;
		
		// The database connection and its initialization state.
		private static var dbConn:SQLConnection = null;
		private static var dbInit:Boolean = false;		
		
		// The schema loaded from the DB
		private static var dbSchema:SQLSchemaResult = null;
		// Version information for the overall schema
		private static var _schemaVer:SchemaInfo = null;

		private static var latestSchema:Boolean = false;
		
		// All registered migrations 
		private static var dbMigrations:Object = {};

    // The schema versions for the database are themselves stored in the 
    // schema_infos table, which is managed by the SchemaInfo model. 
    // The Migrator uses these schema information to decide when and what 
    // migration directives to run. 
    private static function get schemaVer():SchemaInfo {
      if (!_schemaVer) {
        _schemaVer = new SchemaInfo();
      }
      return _schemaVer;
    }
    
    /**
    * Initialize database for use within the application. 
    * The database is stored in the AIR.File.applicationStorageDirectory
    * 
    * @param dbname The name for the SQLite database file. 
    * 
    * @see flash.filesystem.File#applicationStorageDirectory
    **/
		public static function initDB(dbname:String):void {
		  defaultDB = dbname;
			getConnection(dbname);
			if (dbInit) {
    		// 
    		// Load (or attempt to) the db schema and run pending migrations. 
    		// Note: Migration directives are created during instantiation of Migrator
    		// objects throughout the application code. These Migrator objects could 
    		// be static variables, class constants, etc. and could be created in 
    		// any order by the AIR runtime. 
    		// 
    		// The DB.migrate method will cache these migration objects until the
    		// DB is inited, at which point we run them and they effect schema changes.
			  
			  for (var store:String in dbMigrations) {
			    DB.runMigration(dbMigrations[store]);
			  }
			}
		}
		
		/**
		* Obtain and cache a connection to the database. We use synchronous open.
		* @param dbname (optional) The name for the database file
		**/
		public static function getConnection(dbname:String = null):SQLConnection {
		  // This method is public since it is used by the Migrator and Modeler to
		  // cache a SQLConnection for their statements. 
		  if (!dbname && !dbInit && !defaultDB) {
		    throw new Error("DB not inited.");
		  }
			if (!dbConn && !dbInit) {
			  dbname = defaultDB;
    		// The database is stored in the application storage directory 
    		// with the name specified in DB.initDB()			  
				var dbfile:File = File.applicationStorageDirectory.resolvePath(dbname);								
				dbConn = new SQLConnection();
				dbConn.addEventListener(SQLEvent.OPEN, DB.onDBOpen);
				try {
					dbConn.open(dbfile, SQLMode.CREATE);
					dbInit = true;					
				} catch (error:SQLError) {
					trace("ERROR: opening database: " + dbfile.name);
					trace("ERROR:" + error.details);
					return null;
				}
			}
			return dbConn;			
		}
		
		private static function onDBOpen(event:SQLEvent):void	{
      /*trace('onDBOpen ' + event.toString());*/
		}
		
		/**
		* Get and cache the overall database schema. 
		* @param reloadSchema (optional) Set to <code>true</code> to ignore the
		* cached schema and force a reload. 
		* @default false
		* 
		* @return The SQL schema for the database. 
		**/
		public static function getSchema(reloadSchema:Boolean = false):SQLSchemaResult {
			try {
			  // The cached schema is invalidated whenever a migration is run.    		
				if (!latestSchema || reloadSchema) {
					dbConn.loadSchema();
					dbSchema = dbConn.getSchemaResult();
					latestSchema = true;					
				}
			} catch(error:SQLError) {
				trace('DB.getSchema: ERROR ' + error.details);
			}
			return dbSchema; 
		}
		
		/**
		* Get the schema for the specified table. 
		* @param name The table name for which to get the schema
		* @param refresh If <code>true</code> force reload the DB schema. 
		* @default false
		* 
		* @return The SQL schema for the table. Returns null if the table does not 
		* exist in the database.
		* 
		**/
		public static function getTableSchema(name:String, refresh:Boolean = false):SQLTableSchema {
		  // If a refresh is requested, the DB schema is reloaded.  		
			getSchema(refresh);
			if (!dbSchema ||!dbSchema.tables) return null;
			for each (var tbl:SQLTableSchema in dbSchema.tables) {
				if (tbl.name == name) return tbl;
			} 
			return null;
		}
		
		/**
		* Check if the specified table exists
		* @param name The table name to check
		* @return <code>true</code> if table exists, <code>false</code> otherwise
		**/
		public static function existsTable(name:String):Boolean {
			getSchema(true);
			if (!dbSchema || !dbSchema.tables) return false;
			
			var exists:Boolean = false;
			for each (var tbl:SQLTableSchema in dbSchema.tables) {
				if (tbl.name == name) exists = true;
			}
			return exists;
		}
		
		/**
		* Request migration for a particular model. No external usage required.
		* @see Migrator
		**/
		public static function migrate(mobj:IMigratable):void {
			var store:String = mobj.storeName;
			if (!dbInit) {
    		// The migration object is kept pending until the DB is inited.			  
			  dbMigrations[store] = mobj;
			  return;
			}
			runMigration(mobj);
		}
		
		// Actually migrate the given object. 
		// This internal method is invoked if the DB is inited and it is 
		// safe to run the migration. 
		//
		// Checks the schema_infos (if available) to decide which of the 
		// directives need to be run. Absence of schema_infos implies full 
		// migration to bring the schema up-to-date. 
		//
		// Includes special handling for the migration of SchemaInfo model.
		// Tells the migration object what version (fromVer) to migrate from, 
		// and notes in schema_infos the final version (newVer) it migrated to. 
		//
		private static function runMigration(mobj:IMigratable):void {
			var fromVer:uint = 0;			
			var newVer:uint = 0;
			var store:String = mobj.storeName;
			
			if (store == 'schema_infos') {
				fromVer = 0
			} else if (!schemaVer.load({property: store})) {
				fromVer = 0;
			} else {
				fromVer = schemaVer.value as uint;
			}
			// Tell the migratable object the start version
			// Note the final (new) version after migration is performed. 
			newVer = mobj.migrate(fromVer);
			if (newVer != fromVer) {
			  // Invalidate the cached schema, since things have changed
				latestSchema = false;
			}
			if (store != 'schema_infos') {
			  // Store latest schema versions for all tables (except schema_infos)
				if (!schemaVer.load({property: store})) {
					schemaVer.create({property: store, value: newVer});
				} else {
					schemaVer.value = newVer;
					schemaVer.update();
				}				
			}		  
		}
		
		/**
		* Unsupported. Do Not Use.
		* Migrations are automatically carried out as and when required. 
		* Future Use: Force all migrations to run at once.
		**/
		public static function migrateAll():Boolean {
		  // Placeholder - This method is not currently invoked. 
  		// Intended to run all the migrations. 
  		// In practice, this happens in a distributed fashion as each Migrator 
  		// object is instantiated, and calls DB.migrate and is told to migrate
  		// at the appropriate point by DB.runMigration
  		//
  		
			// for each registered migrator
			// get store name
			// check our schema
			// if no table - fromVer = 0, else 
			// fromVer = DB.getSchemaVersion(mStoreName);
			// migratable.migrate
			// if success: DB.setSchemaVersion(mStoreName, vx);
			for each (var store:String in dbMigrations) {
				try {				
					DB.migrate(dbMigrations[store] as IMigratable);
				} catch (error:Error) {
					trace('DB.migrateAll: ERROR migrating ' + store);
					return false; 
				}
			}
			return true;
		}
		
		/**
		* Map an object to its SQL representation appropriate for queries.
		* <p>Deperecation Notice: This method will be removed when we switch to
		* parameterized SQL operations.</p>
		* @param value An Object (String or Date)
		**/
		// 
		public static function sqlMap(value:Object):String {
  		// Puts string values in enclosing quotes 
  		// Transforms date values to canonical string format. 
  		// TODO: check for and escape single-quotes in string.
		  
			if (!value) return 'null';
			if (value is String) {
				if (value.length > 0) return "'" + value + "'";
				if (value.length == 0) return '';
			} else if (value is Date) {
				var rstr:String = "";
				var extr:Array = [
					'fullYearUTC', 'monthUTC', 'dateUTC', 
					null,
					'hoursUTC', 'minutesUTC', 'secondsUTC', 
					null
				] 
				var dstr:Array = [];
				var joiner:String = "-";
				for (var ix:int = 0; ix < extr.length; ix++) {
					var d:uint;
					var s:String;
					if (extr[ix]) {
						d = value[extr[ix]];
						d += (extr[ix] == 'monthUTC') ? 1 : 0;
						s = (d < 10) ? "0" + d.toString() : d.toString();
						dstr.push(s);
					} else {
						rstr += dstr.join(joiner);
						if (ix != extr.length - 1) rstr += " ";
						dstr = [];
						joiner = ":";
					}
				}
				return "'" + rstr + "'";
			}  
			return value.toString();			
		}
		
		/**
		* Map a DB field as specified in migration directives into an appropriate 
		* DB-specific CREATE statement clause after processing field type and 
		* column options.
		* 
		* @param fieldSpec An Array [name, type, options]
		* 
		* @return A SQL field clause for use in CREATE TABLE
		**/
		public static function fieldMap(fieldSpec:Array):String {
			var stmt:String = "";
			if (fieldSpec && fieldSpec.length >= 2) {
				stmt += fieldSpec[0];
				switch(fieldSpec[1]) {
					case Field.Serial:
						stmt += ' INTEGER PRIMARY KEY AUTOINCREMENT';
						break;
					case Field.Integer:
						stmt += ' INTEGER';
						break;
					case Field.Float:
						stmt += ' REAL';
						break;
					case Field.VarChar:
						var lim:String = '255';
						stmt += ' VARCHAR';
						if (fieldSpec.length > 2 && fieldSpec[2].limit) {
							lim = fieldSpec[2].limit.toString();
						}
						stmt += '(' + lim + ')';
						break;
					case Field.DateTime:
						stmt += ' DATETIME';
						break;
					case Field.Text:
						stmt += ' TEXT';
						break;
						
				}
				// Process the options
				if (fieldSpec.length > 2 && fieldSpec[2]) {
					for (var optionKey:String in fieldSpec[2]) {
						var option:String = fieldSpec[2][optionKey].toString();
						switch (optionKey) {
							case 'limit' :
								// Handled under VarChar above.  Do nothing.
								break;
							case 'defaultValue' :
							case 'default': 
								stmt += ' DEFAULT ' + option;
								break;
							case 'primaryKey' :
								if (option == "true") {
									stmt += ' PRIMARY KEY';
								}
								break;
							case 'allowNull' :
								if (option == "false") {
									stmt += ' NOT NULL';
								}
								break;
							case 'unique' :
								if (option == "true") {
									stmt += ' UNIQUE';
								} 
								break;
						}
					}
				}
			}
			return stmt;
		} 				
		
		/** 
		 * Class and Association Mapping to DB tables and fields
		 **/
		// Obtain the unqualified classname
		// Used as the basis for table and foreign key names
		private static function _className(klass:Class):String {
			var name:String = flash.utils.getQualifiedClassName(klass);
			var cp:Array = name.split('::');
			name = cp[cp.length - 1];			
			return name;			
		} 
		
		/**
		* Map a class to a default table name through pluralized inflection. 
		* @param klass A <code>Class</code> or <code>Modeler</code>
		* @return The default table name mapping
		* @see Inflector#pluralize
		* @see Inflector#underscore
		**/
		public static function mapTable(klass:*):String {
			var cls:String = "<unknown>";
			if (klass is Class) cls = _className(klass);
			if (klass is Modeler) cls = klass.className;
			return Inflector.underscore(Inflector.pluralize(cls));
		}
		
		/**
		* Map two classes into a join table name for representing the many-many 
		* relationship between them. 
		* 
		* <p>The table names are sorted alphabetically so as to ensure the same 
		* join table name for a given pair of classes, regardless of the parameter
		* order during the function call.</p>
		* 
		* @param klass1 One of the models (Class or Modeler)
		* @param klass2 The other model class
		* 
		* @return A default join table name 
		* @see mapTable
		* 
		* @example A blog post can have many categories, and a category can apply 
		* to many blog posts. 
		* <listing version="3.0">
		* mapJoinTable(Post, Category);     // ==> "categories_posts"
		* </listing>
		**/
		public static function mapJoinTable(klass1:*, klass2:*):String {
		  var parts:Array = [mapTable(klass1), mapTable(klass2)];
		  return parts.sort().join('_');
		} 
		
		/**
		* Map a class to its default foreign key name in another table.
		* @param klass The model class (Class or Modeler)
		* @return The default foreign key name 
		* @example Foreign key for the Author model
		* <listing version="3.0">
		* mapForeignKey(Author);    // ==> "author_id"
		* </listing>
		**/
		public static function mapForeignKey(klass:*):String {
			var cls:String = "<unknown>";
			if (klass is Class) {
				cls = _className(klass);
			} else if (klass is Modeler) {
				cls = klass.className;
			}
			return Inflector.lowerFirst(cls) + '_id';			
		}				
	}
}
