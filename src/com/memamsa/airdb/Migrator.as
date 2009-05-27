package com.memamsa.airdb
{
	import flash.data.SQLColumnSchema;
	import flash.data.SQLConnection;
	import flash.data.SQLStatement;
	import flash.data.SQLTableSchema;	
	
	public class Migrator implements IMigratable
	{
		private var mStoreName:String = null;		
		private var mKlass:Class = null;
		private var mOptions:Object = null;
		private var mDirectives:Array = null;
		private var mFieldSet:Array = null;
		private var stmt:SQLStatement = null;
		private var dbConn:SQLConnection = null;
		private var createCalled:Boolean = false;

		public function Migrator(klass:Class, options:Object, directives:Array)
		{
			mKlass = klass;
			mOptions = options; 
			mDirectives = directives;
			mFieldSet = [];
			if (options && options.hasOwnProperty('id') && options['id']) {
				column('id', DB.Field.Serial);
			} 
			if (options && options.hasOwnProperty('storage') && options['storage']) {
				mStoreName = options['storage'];
			} else {
				mStoreName = DB.mapTable(mKlass);
			}
			mKlass.prototype.storeName = mStoreName; 
			
			stmt = new SQLStatement();
			dbConn = stmt.sqlConnection = DB.getConnection();						
			
			DB.migrate(this);
			schemate();
		}
	
		/**
		 * IMigratable
		 **/
		public function get storeName():String {
			return mStoreName;
		}

		// run the necessary migrations
		public function migrate(fromVer:uint=0, toVer:uint = 0):uint {
			if (toVer == 0) {
				toVer = mDirectives.length;
			}
			try {
				for (var vx:uint = fromVer; vx < toVer; vx++) {
					mDirectives[vx].call(this, this);
				} 				
			} catch(error:Error) {
				trace("Migrator.migrate: ERROR applying directives\n" + error.message);
				toVer = 0;
			}
			return toVer;
		}
				
		public function schemate():void {
			var tblSchema:SQLTableSchema = DB.getTableSchema(mStoreName);
			if (tblSchema && tblSchema.columns.length > 0) {
				for each (var col:SQLColumnSchema in tblSchema.columns) {
					addFieldToModeler(col.name);
				}
			}
		}
		
		public function addFieldToModeler(name:String):void {
			if (!mKlass.prototype.fieldNames) {
				mKlass.prototype.fieldNames = new Array();
			} 
			mKlass.prototype.fieldNames.push(name);			
		}
		
		public function get hasAutoKeyId():Boolean {
			for (var idx:int = 0; idx < mFieldSet.length; idx++) {
				if (mFieldSet[idx][0] == 'id' && mFieldSet[idx][1] == DB.Field.Serial) {
					return true;
				}
			}
			return false;
		}
		
		// For use within a block call argument to createTable
		public function column(name:String, dataType:uint, options:Object = null):void {
		  if (!createCalled) {
		    mFieldSet.push([name, dataType, options]);  
		  } else {
		    addColumn(name, dataType, options);
		  }			
		}
		
		public function addColumn(name:String, dataType:uint, options:Object):void {
			stmt.text = "ALTER TABLE " + mStoreName + " ADD COLUMN " + 
			  DB.fieldMap([name, dataType, options]);
			trace('addColumn: ' + stmt.text);
			stmt.execute();
		}	
			
		public function removeColumn(name:String):void {
			// ALTER TABLE REMOVE COLUMN 
		} 
		
		public function columnTimestamps():void {
			column('created_at', DB.Field.DateTime);
			column('updated_at', DB.Field.DateTime);
		}
		
		public function createTable(block:Function):void {
			block.call();
			
			var defs:Array = [];
			for (var ix:uint = 0; ix < mFieldSet.length; ix++) {
				trace("ix: " + ix + " : " + mFieldSet[ix].toString());
				defs.push(DB.fieldMap(mFieldSet[ix]));
			}
			stmt.text = "CREATE TABLE IF NOT EXISTS " + mStoreName + 
				" (" + defs.join(',') + ")";
			
			stmt.execute();
			createCalled = true;
		}
		
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
		
		public function belongsTo(klass:Class):void {
		  var bfName:String = DB.mapForeignKey(klass);
		  column(bfName, DB.Field.Integer);
		}
	
	}
}