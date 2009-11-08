package com.memamsa.airdb 
{
	import flash.data.SQLResult;
	import flash.data.SQLStatement;
	import flash.errors.SQLError;
	import flash.utils.Proxy;
	import flash.utils.flash_proxy;
	
	/**
	*  The <code>Associator</code> transparently maps schema relationships into
	*  object aggregations. 
	*  
	*  <p>The <code>Modeler</code> automatically creates appropriate Associators 
	*  using class meta-data. The Associator provides methods for creating and
	*  querying associations between table rows (including through join tables). 
	*  Where necessary, the Associator maps method calls directly to the target 
	*  model, on which additional methods can be invoked.</p>
	*  
	*  <p>The Associator includes support for the following relationships:
	*  <ul>
	*  <li><strong>has_many</strong>: Maps a foreign key for this table into the 
	*  <strong>belongs_to</strong>  counter-part.</li>
	*  <li><strong>has_and_belongs_to_many</strong>: Creates a join table 
	*  mapping the corresponding foreign keys</li>
	*  <li><strong>belongs_to</strong> Specifies the foreign key in this table 
	*  for mapping the association</li>
	*  </ul>
	*  </p>
	*  
	*  <p>Multiple Associations can be specified as class meta-data in the package, 
	*  with the following format. 
	*  <pre>
	*  [Association(name="aname", className="cname", type="atype")]  
	*  
	*  where:
	*     aname = the name by which the association is invoked (e.g. "comments")
	*     cname = FQN of the associated class, e.g. com.example.model.Comment
	*     atype = Association type, e.g. "has_many"
	*  </pre>
	*  <strong>Requires</strong> compiler setting of 
	*  <code>-keep-as3-metadata+=Association</code>
	*  </p>
	*  
	*  @example A blog Post belongs-to author and has-many comments: 
	*  <listing version="3.0">
	*  package example.model {
 	*   [Association(type="has_many", name="comments", className="example.model.Comment")]
 	*   [Association(type="belongs_to", name="author", className="example.model.Person")]
	*   dynamic class Post extends Modeler {
	*   }
	*  }
	*  var post:Post = Modeler.findery(Post, {id: 3});
	*  trace(post.author.name);
	*  // Find comments since 2009-08-01
	*  post.comments.findAll({
	*     select: "*, strftime("%Y-%m-%d, created_at) as cd", 
	*     conditions: "cd > '2009-08-01'"
	*  });
	*  </listing>
	*  
	**/
	public class Associator extends Proxy
	{
		public static const HAS_AND_BELONGS_TO_MANY:String = "has_and_belongs_to_many";
		public static const HAS_ONE:String = "has_one";
		public static const HAS_MANY:String = "has_many";
		public static const BELONGS_TO:String = "belongs_to";
		
		public static const ALL:int = 0;
		
		// Associator maps a source property to a target object
		// Invoked methods are handled by the Associator itself or passed onto 
		// the target object methods
		// 
		private var mySource:Modeler;   // source invoking association as property
		private var myTarget:Modeler;   // target object whose methods are invoked
		private var myType:String;      // association type
		private var targetKlass:Class;	// class of the target
		private var joinTable:String;   // for has_and_belongs_to_many
		private var mPropName:String;		// association name as property of source
		private var targetForeignKey:String;    // foreign key for target model
		private var sourceForeignKey:String;    // join table foreign key for source
		private var targetStoreName:String;     // table name for target
		
		/**
		* Construct an associator to map between two models representing database
		* tables. The source is the subject and the target is the object of the
		* relationship. e.g. If a customers has-many orders, then Customer is the
		* source and Order is the target. 
		* 
		* @param source A model (sub-class of <code>Modeler</code>) 
		* <strong>object</strong> which is the subject (source) of the assocation. 
		* 
		* @param target A <code>Modeler</code> derived <strong>class</strong> 
		* as the target of the association. 
		* 
		* @param type The association type. 
		**/
		public function Associator(source:Modeler, target:Class, type:String) {
		  // store information and generated mappings
			mySource = source;
			targetKlass = target;
			sourceForeignKey = DB.mapForeignKey(source);
			targetForeignKey = DB.mapForeignKey(target);
			targetStoreName = DB.mapTable(target);
			
			myType = type;
			try {
			  if (myType == BELONGS_TO) {
			    // Find the specific target corresponding to this source object. 
			    myTarget = Modeler.findery(target, {id: mySource[targetForeignKey]});
			  } else if (myType == HAS_ONE) {
			    var keyval:Object = new Object();
			    keyval[sourceForeignKey] = mySource['id'];
			    myTarget = Modeler.findery(target, keyval);
			  } else {
			    // In other cases, we just need a generic target model on which we 
			    // can invoke appropriate query operations.
			    myTarget = new target();
			  }				
			} catch(e:Error) {
				trace('Associator ERROR instantiating target class');
			}
			
			if (myType == HAS_AND_BELONGS_TO_MANY) {
			  // for many-many associations, we note the join table for efficiently
			  // constructing queries later. 
				joinTable = DB.mapJoinTable(source, target);
			}
		}
		
		/**
		* Get the table name for the association target 
		**/
		public function get target():* {
			return myTarget as targetKlass;
		}
		
		/**
		* Set the target for HAS_ONE or BELONGS_TO associations. 
		* 
		* @param obj The <code>Modeler</code> sub-class object that is the target
		* of this association.
		* 
		* @example Change the author for a blog post
		* <listing version="3.0">
		* // post belongs_to author 
		* var post:Post = Modeler.findery(Post, {id: 3});
		* var user:User = Modeler.findery(User, {name: 'someuser'});
		* post.author = user;
		* </listing>
		**/
		public function set target(obj:*):void {
		  if (myType == HAS_MANY || myType == HAS_AND_BELONGS_TO_MANY) {
		    throw new Error(myType + ': Cannot directly set target. Use push');
		  }		  
		  if (!(obj is Modeler)) {
		    throw new Error('Associator#target=. Expect Modeler ' + obj);
		  }
		  if (!(obj is targetKlass)) {
		    throw new Error(myType + ':' + targetKlass + " Unexpected target " + obj);
		  }
		  // HAS_ONE and BELONGS_TO target, if it exists is not automatically 
		  // overridden
		  if (myTarget) {
		    throw new Error(myType + ': target exists. Explicitly remove()');
		  }
		  if (myType == HAS_ONE) {
		    if (!mySource['id'] && mySource.unsaved) mySource.save();
		    if (!mySource['id']) {
		      throw new Error(myType + ":" + targetStoreName + ': source ID unknown');
		    }
	      obj[sourceForeignKey] = mySource['id'];
	      obj.save();
	      
	      var keyval:Object = new Object();
	      keyval[sourceForeignKey] = mySource['id'];
	      myTarget = Modeler.findery(targetKlass, keyval);
	      
		  } else if (myType == BELONGS_TO) {
		    if (!obj['id'] && obj.unsaved) obj.save();
		    if (!obj['id']) {
		      throw new Error(myType + ":" + targetStoreName + ": target ID unknown");
		    }
		    mySource[targetForeignKey] = obj['id'];
		    mySource.save();
		    
		    myTarget = Modeler.findery(targetKlass, {id: obj['id']});
		  }
      if (!myTarget) {
        throw new Error(myType + ' Setting target failed');
      }		  
		}
		
		/**
		* Count the number of associated objects. 
		**/
		public function get count():int {
			if (!mySource['id']) return 0;
			if (myType == HAS_ONE || myType == BELONGS_TO) {
			  return ((typeof(myTarget) != 'undefined' && myTarget) ? 1 : 0);
			}
			if (myType == HAS_AND_BELONGS_TO_MANY) {
				var query:Object = construct_query();
				return myTarget.countAll(query);
			}
			if (myType == HAS_MANY) {
			  var cond:String = sourceForeignKey + '=' + mySource['id'];
			  return myTarget.countAll({conditions:cond});
			}
			return -1;
		}
		
		/**
		* List all target objects. Equivalent to findAll({})
		* 
		* @see Associator#findAll
		**/
		public function list(params:Object = null):Array {
			if (!params) params = {};
			return findAll(params);
		}
		
		/**
		* Query associated objects
		* 
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
		* @return List of Objects representing the query result.
		* 
		* @see Modeler#findAll
		* 
		**/
		public function findAll(query:Object):Array {
			if (!mySource['id']) return [];
			if (myType == HAS_AND_BELONGS_TO_MANY) {
				var query:Object = construct_query(query);
				return myTarget.findAll(query);
			} else if (myType == HAS_MANY) {
			  return myTarget.findAll({conditions: sourceForeignKey + '=' + mySource['id']});
			}
			return [];
		}
		
		/**
		* Set attributes on the association. 
		* 
		* Associations of type has_and_belongs_to_many can have attributes as
		* part of the mapping between the source and target models. Use setAttr
		* to set the values for these attributes, either for a single target
		* or for all of the many targets associated with the source.
		* 
		* @example A blog Post has many Tags and a Tag is associated with many Post
		* A logged in reader (User) can vote on the tagggings for the post. We can
		* track the vote counts for each tagging
		* 
		* [Association type="has_and_belongs_to_many" name="tags" class="example.Tag"]
		* dynamic public class Post extends Modeler {
		* 		private static var migrations:Migrator = new Migrator(
		*				Post, {id: true}, 
		*				[
		*					function(my:Migrator):void {
		*						my.createTable(function():void {
		*							my.column('name', DB.Field.VarChar, {limit: 255});
		*							my.columnTimestamps();
		*						});
		*					}, 
		*					function(my:Migrator):void {
		*						var tagVotesCol:Array = ['votes', DB.Field.Integer, {
		*							'default': 1}
		*						];					
		*						my.joinTable(Photo, [tagVotesCol]);
		*					},
		*				]
		* 		)
		* }
		* // Push as usual to create a new association and corresponding join row
		* var post:Post = new Post();
		* var flex:Tag = new Tag().find({name: 'flex'});
		* post.tags.push(flex);
		* 
		* // Update the votes for a given for some post
		* numVotes = post.tags.getAttrVal('votes', flex.id);		
		* post.tags.setAttr({votes: numVotes + 1}, flex.id);
		* 
		* // Reset the votes for all tags for a given post
		* post.tags.setAttr({votes: 1});
		*
		* @param keyvals An Object whose keys map to the column names for the join
		* table attributes. The corresponding values are used to update the fields
		* for the matching join table record(s).
		* 
		* @param target A Modeler object or an Integer rowID to match a specific
		* join table row. This value is used to match the foreign key field 
		* corresponding to the association target. Implicit in the call to this 
		* method is the source, since the method was invoked via the source object
		* for the association. 
		* @default ALL Acts on all the targets associated with the source.
		* 
		* @return The number of join table rows updated. 
		* 
		* @see Migrator#joinTable
		* @see findAllByAttr
		* @see countAllByAttr
		**/
		public function setAttr(keyvals:Object, target:* = Associator.ALL):int {
			if (myType != HAS_AND_BELONGS_TO_MANY) {
				throw new Error(myType + '. Join table attributes unsupported');
			}
			var sql:String = "UPDATE " + joinTable + " SET ";
			var uc:Array = [];
			for (var key:String in keyvals) {
				uc.push(key + '=' + DB.sqlMap(keyvals[key]));
			}
			sql += uc.join(', ');
			sql += joinConditions({}, target);
			var result:SQLResult = DB.execute(sql);
			if (!result || !result.rowsAffected) {
				throw new Error('setAttr. Update failed');
			}
			return result.rowsAffected;
		}
		
		/**
		* Find all association targets with matching association attributes.
		* 
		* Associations of type has_and_belongs_to_many can have attributes as
		* part of the mapping between the source and target models. Use this 
		* method to find all associated targets matching the specified 
		* association attributes.
		* 
		* @param keyvals An Object whose keys map to the column names for the join
		* table attributes, and whose values specify the conditions for the field 
		* values in the query. 
		* 
		* @see setAttr
		* @see countAllByAttr
		* @see Migrator#joinTable		
		**/
		public function findAllByAttr(keyvals:Object):Array {
			if (myType != HAS_AND_BELONGS_TO_MANY) {
				throw new Error(myType + '. Join table attributes unsupported');
			}
			var cond:String = "SELECT " + targetForeignKey + " FROM " + joinTable;
			cond += joinConditions(keyvals, ALL);
			return myTarget.findAll({
				conditions: 'id in (' + cond + ')'
			});
		}
		
		/**
		* Get the value for a given attribute for a specific target 
		*
		* @param name The attribute name
		* 
		* @param target The Modeler object, or Integer id for a specific
		* target. Implicit in the call is a particular source object, thus 
		* defining a particular association corresponding to a single row in
		* the join table. 
		* 
		* @return The value for the association attribute.
		* 
		* @see setAttr
		**/
		public function getAttrVal(name:String, target:*):* {
			if (myType != HAS_AND_BELONGS_TO_MANY) {
				throw new Error(myType + '. Join table attributes unsupported');
			}
			var sql:String = "SELECT " + name + " FROM " + joinTable;
			sql += joinConditions({}, target);
			var result:SQLResult = DB.execute(sql);
			if (result && result.data && result.data.length >= 1) {
				return result.data[0][name];
			}
			return null;
		}
		
		/** 
		* Count the number of associated targets matching specified criteria.
		* 
		* @param keyvals An Object whose key-value pairs specify column names
		* and their field values in the join table. 
		* 
		* @target A Modeler or Integer to specify a particular association 
		* target. Possible return values in such a case can be 0 or 1. 
		* 
		* @return An integer count. 
		* 
		* @see setAttr
		* @see findAllByAttr
		* @see Migrator#joinTable		
		**/
		public function countByAttr(keyvals:*, target:* = Associator.ALL):int {
			if (myType != HAS_AND_BELONGS_TO_MANY) {
				throw new Error(myType + '. Join table attributes unsupported');
			}
			var sql:String = "SELECT COUNT(*) as count FROM " + joinTable;
			sql += joinConditions(keyvals, target);
			var result:SQLResult = DB.execute(sql);
			if (result && result.data && result.data.length >= 1) {
				return result.data[0].count;
			} 
			return -1;
		}
		
		// construct the WHERE clause for join table queries. 
		private function joinConditions(keyvals:*, target:*):String {			
			if (mySource.unsaved) mySource.save();
			if (!mySource['id']) {
				throw new Error(targetStoreName + ': Source ID is unknown');
			}			
			var conditions:String = " WHERE ";
			conditions += '(' + sourceForeignKey + " = " + mySource['id'] + ')';
			if (keyvals is String) {
				conditions += ' AND (' + keyvals + ')';
			} else if (keyvals is Object) {
				var cond:Array = [];
				for (var key:String in keyvals) {
					cond.push('(' + key + " = " + DB.sqlMap(keyvals[key]) + ')');
				}
				if (cond.length > 0) {
					conditions += ' AND ' + cond.join(' AND ');
				}
			}
			if (target && target is Modeler) target = target.id;
			if (target && target is Number && target != Associator.ALL) {
				conditions += ' AND (' + targetForeignKey + ' = ' + target + ')'; 
			}
			return conditions;
		}
		
		/**
		* Create an association between the source and the specified target object.
		* Saves the source and the target if either of them are new records. 
		* 
		* @param obj The target object to be associated with this source model. 
		* This can be an object of a <code>Modeler</code> sub-class or an integer
		* which is interpreted as the <strong>id</strong> field value for the target.
		* 
		* @param noDups Specifies whether duplicate associations are disallowed, 
		* particularly for <code>has_and_belongs_to_many</code> associations. 
		* @default true, which means no duplicates. 
		* 
		* @return <code>true</code> if association was successfully made, otherwise
		* <code>false</code>.
		* 
		* @example Add another comment to a blog post. 
		* <listing version="3.0">
		* var post:Post = Modeler.findery(Post, {id: 1});
		* // Push (and saves) new comment
		* post.comments.push(new Comment({title: '1st', text: 'i wuz here'}));
		* </listing>
		**/
		public function push(obj:*, noDups:Boolean = true):Boolean {
		  // cannot push in case of one-one or belongs-to
		  // Use setProperty via "=" operator
		  if (myType == HAS_ONE || myType == BELONGS_TO) {
		    throw new Error(myType + ":Cannot push. Set properties directly");
		  }
		  // prepare source and target
		  var targetId:int = 0;
		  
			if (mySource.unsaved) mySource.save();
			if (!mySource['id']) {
				throw new Error(targetStoreName + ': Source ID is unknown');
			}
		  
			if (obj is Modeler) {
			  if (obj.className != myTarget.className) return false;
			  // H-M with object specified is taken care of right here.
		    if (myType == HAS_MANY && obj[sourceForeignKey] != mySource['id']) {
		      obj[sourceForeignKey] = mySource['id'];
		      return obj.save(); 
		    }			  
			  if (obj.unsaved) {
			  	obj.save();
			  }
			  if (!obj['id']) {
			    throw new Error(targetStoreName + ": target has no id");
			  }
			  targetId = obj['id'];
			} 
			if (obj is Number) {
			  targetId = obj;
			}			
			
			if (myType == HAS_AND_BELONGS_TO_MANY) {
			  return find_or_create(mySource['id'], targetId, noDups);
			} else if (myType == HAS_MANY) {
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
		
		/** 
		* Remove an association which the given object might have with this
		* source. 
		* 
		* @param obj The target object(s) to be dis-associated from this source model. 
		* The parameter can be: 
		* <ul>
		* <li>A single object instance of a <code>Modeler</code> sub-class</li>
		* <li>An <code>Array</code> of <code>Modeler</code> objects</li>
		* <li>An integer as the <strong>id</strong> field value for the target</li>
		* <li>An <code>Array</code> of target ids</li>
		* </ul>
		* 
		* @return <code>true</code> if association was successfully made, otherwise
		* <code>false</code>.
		* 
		**/
		// remove the specified object from the associated set
		// provide either the actual object or simply its primary key.
		public function remove(obj:*):Boolean {
		  if (myType == HAS_ONE || myType == BELONGS_TO) {
		    return myTarget.remove();
		  }
			if (myType == HAS_AND_BELONGS_TO_MANY) {
				if (obj is Modeler && 
				  obj.className != myTarget.className &&
				  obj.className != mySource.className) {
				  throw new Error(myType + '.remove: Not an associated source or target');
				}
				var anchorCond:String = sourceForeignKey + ' = ' + mySource['id'];
				var toDelete:String;
				var ids:Array = [];
				if (obj is Modeler && obj.className == mySource.className) {
				  toDelete = "";
				} else {
				  anchorCond += ' AND ' + targetForeignKey;
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
					toDelete = ' IN (' + ids.join(',') + ')';
				}
				var stmt:SQLStatement = new SQLStatement();
				stmt.sqlConnection = DB.getConnection();
				stmt.text = "DELETE FROM " + joinTable + " WHERE " + anchorCond + toDelete;
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
			if (myType == BELONGS_TO || myType == HAS_ONE) {
			  return myTarget.hasOwnProperty(name);
		  } 
		  return false;  			
		} 
		
		override flash_proxy function getProperty(name:*):* {
			if (myType == BELONGS_TO || myType == HAS_ONE) return myTarget[name];
			return undefined;
		}
		
		override flash_proxy function setProperty(name:*, value:*):void {
			if (myType == BELONGS_TO || myType == HAS_ONE) myTarget[name] = value;
		}
		
		override flash_proxy function callProperty(name:*, ...args):* {
			if (myType == BELONGS_TO || myType == HAS_ONE) {
				return myTarget[name.toString()].apply(myTarget, args);
			}
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