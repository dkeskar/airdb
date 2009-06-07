package com.memamsa.airdb
{
	import flash.data.SQLStatement;
	import flash.data.SQLResult;	
	import flash.errors.SQLError;
	import flash.utils.Proxy;
	import flash.utils.flash_proxy;
	
	/**
	 * Manages the load of associated objects
	 **/
	public class Associator extends Proxy
	{
		public static const Map:Object = {
			has_and_belongs_to_many : DB.Has.AndBelongsToMany,
			has_one: DB.Has.One,
			has_many: DB.Has.Many,
			belongs_to: DB.Has.BelongsTo
		};
		
		private var mySource:Modeler;
		private var myTarget:Modeler;
		private var myType:uint;
		private var joinTable:String;
		private var mPropName:String;						// triggered by what property name
		private var targetForeignKey:String;
		private var sourceForeignKey:String;
		private var targetStoreName:String;
		
		public function Associator(source:Modeler, target:Class, type:String) {
			mySource = source;
			sourceForeignKey = DB.mapForeignKey(source);
			targetForeignKey = DB.mapForeignKey(target);
			targetStoreName = DB.mapTable(target);
			
			myType = Associator.Map[type];
			try {
			  if (myType == DB.Has.BelongsTo) {
			    myTarget = Modeler.findery(target, {id: mySource[targetForeignKey]});
			  } else {
			    myTarget = new target();
			  }				
			} catch(e:Error) {
				trace('Associator ERROR instantiating target class');
			}
			
			if (myType == DB.Has.AndBelongsToMany) {
				joinTable = DB.mapJoinTable(source, target);
			}
		}
		
		public function get target():String {
			return targetStoreName;
		}
		
		// returns a count of the number of associated objects
		public function get count():int {
			if (!mySource['id']) return 0;
			if (myType == DB.Has.One || myType == DB.Has.BelongsTo) {
				return 1;
			}
			if (myType == DB.Has.AndBelongsToMany) {
				var query:Object = construct_query();
				return myTarget.countAll(query);
			}
			return -1;
		}
		
		// returns a list of all target objects, with order and limit as specified.
		// intended as a quick syntactic way to say "list" 
		// use findAll directly if you need to limit the results by conditions, etc. 
		public function list(params:Object = null):Array {
			if (!params) params = {};
			return findAll(params);
		}
		
		// find objects with specified query params provided as predicates
		// allowable keys: select, joins, conditions, order, limit  
		public function findAll(query:Object):Array {
			if (!mySource['id']) return [];
			if (myType == DB.Has.AndBelongsToMany) {
				var query:Object = construct_query(query);
				return myTarget.findAll(query);
			} else if (myType == DB.Has.Many) {
			  return myTarget.findAll({conditions: sourceForeignKey + '=' + mySource['id']});
			}
			return [];
		}
		
		// add specified object(s) to the associated set of objects
		// The object to be added can be specified either by its primary id
		// or by providing the actual Modeler sub-class object
		// By default, if an association exists, duplicates are not added. 
		public function push(obj:*, noDups:Boolean = true):Boolean {
		  // prepare source and target
		  var targetId:int = 0;
		  
			if (mySource.unsaved) mySource.save();
			if (!mySource['id']) {
				trace('Associator.' + targetStoreName + '.push: source ID unknown');
				throw 'Unknown ID';
			}
		  
			if (obj is Modeler) {
			  if (obj.className != myTarget.className) return false;
			  // H-M with object specified is taken care of right here.
		    if (myType == DB.Has.Many && obj[sourceForeignKey] != mySource['id']) {
		      obj[sourceForeignKey] = mySource['id'];
		      return obj.save(); 
		    }			  
			  if (obj.unsaved) obj.save();
			  if (!obj['id']) {
			    trace('Associator.' + targetStoreName + '.push: target has no ID');
			    throw "UnknownID";
			  }
			  targetId = obj['id'];
			} 
			if (obj is Number) {
			  targetId = obj;
			}			
			
			if (myType == DB.Has.AndBelongsToMany) {
			  return find_or_create(mySource['id'], targetId, noDups);
			} else if (myType == DB.Has.Many) {
			  var rc:int = 0;
			  rc = myTarget.updateAll('id = ' + targetId, sourceForeignKey + ' = ' + mySource['id']);
			  return (rc == 1) ? true : false;
			}
			return false;
		}
		
    // Find or create using SQL statements
    // Used by various kinds of push associators
		private function find_or_create(sourceId:int, targetId:int, noDup:Boolean = true) {
      var stmt:SQLStatement = new SQLStatement();
      stmt.sqlConnection = DB.getConnection();
      
		  if (noDup) {
		    stmt.text = "SELECT " + targetForeignKey + " FROM " + joinTable + 
			      " WHERE " + sourceForeignKey + " = " + mySource['id'] + 
			      " AND " + targetForeignKey + " = " + targetId;
			  try {
			    stmt.execute();
			    var result:SQLResult = stmt.getResult();
			    if (result && result.data) {
			      trace('Association already exists and no duplicates.');
			      return true;
			    }
			    trace("Associator.push: Proceeding, noDup and nothing found.");
			  } catch(error:SQLError) {
			    trace('ERROR: Associator.push: ' + error.details);
			  }		    
		  }
		  stmt.text = "INSERT INTO " + joinTable + 
				' (' + sourceForeignKey + ',' + targetForeignKey + ') VALUES (' + 
				  sourceId + ',' + targetId + ')';
			try {
				stmt.execute();
				return true;
			} catch(error:SQLError) {
				trace('ERROR: Associator.push: ' + error.details);
			}
			return false;
		}
		
		// remove the specified object from the associated set
		// provide either the actual object or simply its primary key.
		public function remove(obj:*):Boolean {
			if (myType == DB.Has.AndBelongsToMany) {
				if (obj is Modeler && obj.className != myTarget.className) return false;
				var ids:Array = [];
				if (obj is Modeler) {
					ids.push(obj['id']);
				} else if (obj is Array) {
					for (var ix:int; ix < obj.length; ix++) {
						var ao:* = obj[ix];
						if (ao is Modeler && ao['className'] == myTarget.className) {
							ids.push(ao['id']);
						} else if (ao is int || ao is uint) {
							ids.push(ao);
						}
					}
				}
				var stmt:SQLStatement = new SQLStatement();
				stmt.sqlConnection = DB.getConnection();
				stmt.text = "DELETE FROM " + joinTable + " WHERE " + 
					sourceForeignKey + ' = ' + mySource['id'] + ' AND ' + 
					targetForeignKey + ' IN (' + ids.join(',') + ')';
				try {
					stmt.execute();
					return true;				
				} catch (error:SQLError) {
					trace('Associator.remove: ' + error.details);
				} 
			}
			return false;	
		}
		
		override flash_proxy function hasProperty(name:*):Boolean {
			if (myType == DB.Has.BelongsTo) return myTarget.hasOwnProperty(name);
			return false;
		} 
		
		override flash_proxy function getProperty(name:*):* {
		  if (myType == DB.Has.BelongsTo) return myTarget[name];
			return undefined;
		}
		
		override flash_proxy function setProperty(name:*, value:*):void {
		  if (myType == DB.Has.BelongsTo) myTarget[name] = value;
		}
		
		override flash_proxy function callProperty(name:*, ...args):* {
			return false;
		}
		
		
		private function construct_query(params:Object = null):Object {
			var query:Object = {
				joins: 'INNER JOIN ' + joinTable + ' ON ' + 
								targetStoreName + '.id = ' + joinTable + '.' + targetForeignKey,
				conditions: joinTable + '.' + sourceForeignKey + ' = ' + mySource['id']									
			}
			if (params && params.conditions) {
				query.conditions = '(' + query.conditions + ') AND (' + params.conditions + ')'; 
			}
			for (var key:String in params) {
				if (key == 'limit' || key == 'order') {
					query[key] = params[key]
				}					
			}
			return query;
		}
	}
}