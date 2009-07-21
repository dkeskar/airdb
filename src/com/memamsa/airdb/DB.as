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
		// Currently all models in the application stored in the same DB.
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

    private static function get schemaVer():SchemaInfo {
      if (!_schemaVer) {
        _schemaVer = new SchemaInfo();
      }
      return _schemaVer;
    }
    
		// initialize database etc. 
		public static function initDB(dbname:String):void {
		  defaultDB = dbname;
			getConnection(dbname);
			if (dbInit) {
			  for (var store:String in dbMigrations) {
			    DB.runMigration(dbMigrations[store]);
			  }
			}
		}
		
		// get a connection to the database
		// Sync only supported
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
		
		// get the schema (cached) 
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
		
		public static function getTableSchema(name:String, refresh:Boolean = false):SQLTableSchema {
			getSchema(refresh);
			if (!dbSchema ||!dbSchema.tables) return null;
			for each (var tbl:SQLTableSchema in dbSchema.tables) {
				if (tbl.name == name) return tbl;
			} 
			return null;
		}
		
		public static function existsTable(name:String):Boolean {
			getSchema(true);
			if (!dbSchema || !dbSchema.tables) return false;
			
			var exists:Boolean = false;
			for each (var tbl:SQLTableSchema in dbSchema.tables) {
				if (tbl.name == name) exists = true;
			}
			return exists;
		}
		
		public static function migrate(mobj:IMigratable):void {
			var store:String = mobj.storeName;
			if (!dbInit) {
			  dbMigrations[store] = mobj;
			  return;
			}
			runMigration(mobj);
		}
		
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
			newVer = mobj.migrate(fromVer);
			if (newVer != fromVer) {
				latestSchema = false;
			}
			if (store != 'schema_infos') {
				if (!schemaVer.load({property: store})) {
					schemaVer.create({property: store, value: newVer});
				} else {
					schemaVer.value = newVer;
					schemaVer.update();
				}				
			}		  
		}
		
		// run all the migrations
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
		
		// Map a DB field to an appropriate DB-specific statement
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
		private static function _className(klass:Class):String {
			var name:String = flash.utils.getQualifiedClassName(klass);
			var cp:Array = name.split('::');
			name = cp[cp.length - 1];			
			return name;			
		} 
		public static function mapTable(klass:*):String {
			var cls:String = "<unknown>";
			if (klass is Class) cls = _className(klass);
			if (klass is Modeler) cls = klass.className;
			return Inflector.underscore(Inflector.pluralize(cls));
		}
		
		public static function mapJoinTable(klass1:*, klass2:*):String {
			return mapTable(klass1) + '_' + mapTable(klass2);
		} 
		
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