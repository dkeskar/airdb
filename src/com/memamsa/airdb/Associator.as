package com.memamsa.airdb
{
	import flash.data.SQLResult;
	import flash.data.SQLStatement;
	import flash.errors.SQLError;
	import flash.utils.Proxy;
	import flash.utils.flash_proxy;
	
	/**
	*  Associator
	*  Manages the load of associated objects that map DB relationships into 
	*  object aggregation with support for chaining method invocations.
	*  
	*  Facilitates object relational modeling of schema relationships such as 
	*  "has-many", "belongs-to", "many-many". For example: 
	*  
	*  post belongs-to author and author has-many comments: 
	*  post.author.comments.list();
	*  
	*  Several associations can be specified as Class meta-data in the package
	*  with the following format: 
	*  
	*  [Association(name="aname", className="cname", type="atype")]  
	*  
	*  where:
	*     aname = the name by which the association is invoked (e.g. "comments")
	*     cname = FQN of the associated class, e.g. com.example.model.Comment
	*     atype = Association type, e.g. "has_many"
	**/
	public class Associator extends Proxy
	{
	  // String names and const mappings for supported association types
		public static const Map:Object = {
			has_and_belongs_to_many : DB.Has.AndBelongsToMany,
			has_one: DB.Has.One,
			has_many: DB.Has.Many,
			belongs_to: DB.Has.BelongsTo
		};
		
		// Associator maps a source property to a target object
		// Invoked methods are handled by the Associator itself or passed onto 
		// the target object methods
		// 
		private var mySource:Modeler;   // source invoking association as property
		private var myTarget:Modeler;   // target object whose methods are invoked
		private var myType:uint;        // association type
		private var joinTable:String;   // for has_and_belongs_to_many
		private var mPropName:String;		// association name as property of source
		private var targetForeignKey:String;    // foreign key for target model
		private var sourceForeignKey:String;    // join table foreign key for source
		private var targetStoreName:String;     // table name for target
		
		// Construct an associator. 
		// The source and targets are Modeler objects, although the target is 
		// specified just via the classname.
		public function Associator(source:Modeler, target:Class, type:String) {
		  // store information and generated mappings
			mySource = source;
			sourceForeignKey = DB.mapForeignKey(source);
			targetForeignKey = DB.mapForeignKey(target);
			targetStoreName = DB.mapTable(target);
			
			myType = Associator.Map[type];
			try {
			  if (myType == DB.Has.BelongsTo) {
			    // Find the specific target corresponding to this source object. 
			    myTarget = Modeler.findery(target, {id: mySource[targetForeignKey]});
			  } else {
			    // In other cases, we just need a generic target model on which we 
			    // can invoke appropriate query operations.
			    myTarget = new target();
			  }				
			} catch(e:Error) {
				trace('Associator ERROR instantiating target class');
			}
			
			if (myType == DB.Has.AndBelongsToMany) {
			  // for many-many associations, we note the join table for efficiently
			  // constructing queries later. 
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
				throw new Error(targetStoreName + ': Source ID is unknown');
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
			    throw new Error(targetStoreName + ": target has no id");
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
		private function find_or_create(sourceId:int, targetId:int, noDup:Boolean = true):Boolean {
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