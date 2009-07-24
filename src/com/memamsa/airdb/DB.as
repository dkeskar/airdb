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
	*  DB is named and initialized with DB.initDB somewhere in the app init. 
	*  AirDB abstracts the schema management, query operations and table 
	*  associations using Migrator, Modeler and Associator respectively. 
	*  
	*  This class is an unenforced singleton, providing only _static_ methods.
	**/
	public class DB
	{
		// Enumerations for Stored Data Types 
		public static const Field:Object = {
			Serial: 1, Integer: 2, VarChar: 3, DateTime: 4, Text: 5, Blob: 6, Float: 7
		}
		// Enumerations for Association types
		public static const Has:Object = {
			One: 1, Many: 2, AndBelongsToMany: 3, BelongsTo: 4
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
    
		// Initialize database with the specified name.
		// Load (or attempt to) the db schema and run pending migrations. 
		// Note: Migration directives are created during instantiation of Migrator
		// objects throughout the application code. These Migrator objects could 
		// be static variables, class constants, etc. and could be created in 
		// any order by the AIR runtime. 
		// 
		// The DB.migrate method will cache these migration objects until the
		// DB is inited, at which point we run them and they effect schema changes.
		public static function initDB(dbname:String):void {
		  defaultDB = dbname;
			getConnection(dbname);
			if (dbInit) {
			  for (var store:String in dbMigrations) {
			    DB.runMigration(dbMigrations[store]);
			  }
			}
		}
		
		// get a connection to the database (synchronously)
		// The database is stored in the application storage directory 
		// with the name specified in DB.initDB()
		public static function getConnection(dbname:String = null):SQLConnection {
		  if (!dbname && !dbInit && !defaultDB) {
		    throw new Error("DB not inited.");
		  }
			if (!dbConn && !dbInit) {
			  dbname = defaultDB;
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
		
		// Get the overall database schema. 
		// Returns previously cached schema unless a reload is forced.
		// The cached schema is invalidated whenever a migration is run.
		public static function getSchema(reloadSchema:Boolean = false):SQLSchemaResult {
			try {
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
		
		// Get the schema for the specified table. 
		// If a refresh is requested, the DB schema is reloaded.
		public static function getTableSchema(name:String, refresh:Boolean = false):SQLTableSchema {
			getSchema(refresh);
			if (!dbSchema ||!dbSchema.tables) return null;
			for each (var tbl:SQLTableSchema in dbSchema.tables) {
				if (tbl.name == name) return tbl;
			} 
			return null;
		}
		
		// Check if the specified table exists
		public static function existsTable(name:String):Boolean {
			getSchema(true);
			if (!dbSchema || !dbSchema.tables) return false;
			
			var exists:Boolean = false;
			for each (var tbl:SQLTableSchema in dbSchema.tables) {
				if (tbl.name == name) exists = true;
			}
			return exists;
		}
		
		// Public invocation method to migrate the specified object. 
		// The migration object is kept pending until the DB is inited.
		public static function migrate(mobj:IMigratable):void {
			var store:String = mobj.storeName;
			if (!dbInit) {
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
		
		// Placeholder - This method is not currently invoked. 
		// Intended to run all the migrations. 
		// In practice, this happens in a distributed fashion as each Migrator 
		// object is instantiated, and calls DB.migrate and is told to migrate
		// at the appropriate point by DB.runMigration
		//
		public static function migrateAll():Boolean {
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
		
		// Map an object to its SQL representation appropriate for queries.
		// Puts string values in enclosing quotes 
		// Transforms date values to canonical string format. 
		//
		// TODO: check for and escape single-quotes in string.
		public static function sqlMap(value:Object):String {
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
		
		// Map a DB field as specified in migration directives into an 
		// appropriate DB-specific CREATE statement clause after processing
		// field type and column options.
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
		
		// Given a class, find the table name through pluralized inflection
		// e.g. Comment -> comments, SchemaInfo -> schema_infos
		public static function mapTable(klass:*):String {
			var cls:String = "<unknown>";
			if (klass is Class) cls = _className(klass);
			if (klass is Modeler) cls = klass.className;
			return Inflector.underscore(Inflector.pluralize(cls));
		}
		
		// Given two classes representing Models create a join table to
		// model the many-many relationship between them. 
		// Uses alphabetic sorting to ensure deterministic join table no 
		// matter what order the classes are presented. 
		// e.g. (Post, Category) -> categories_posts
		public static function mapJoinTable(klass1:*, klass2:*):String {
		  var parts:Array = [mapTable(klass1), mapTable(klass2)];
		  return parts.sort().join('_');
		} 
		
		// Given a class, returns the appropriate foreign_key name
		// e.g. (Author) -> author_id
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
