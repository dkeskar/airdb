package com.memamsa.airdb
{
	/**
	* The <code>Relater</code> provides a declarative mechanism to specify 
	* associations between Modeler objects. 
	*
	* <p>This method is an alternative (and recommended) way. Its better than using
	* class meta-data, since it does not require any external compiler setting, 
	* allows compile-time checking of association code, provides a richer set of
	* options, including the ability to explicitly specify foreign key column 
	* names.</p>
	* 
	* <p>The <code>Associator</code> still forms the basis for accessing and 
	* operating on associations. The <code>Relater</code> simply provides a 
	* declarative mechanism. In addition to the previously allowed associations
	* the Relater allows a has_many_through type, specified as a has_many with
	* additional options.</p>
	* 
	* <p>Options supported (depending on association): 
	* <ul>
	* <li><strong>class_name</strong>: FQN for the associated Modeler</li>
	* <li><strong>foreign_key</strong>: DB column used to lookup the association</li>
	* <li><strong>through</strong>: m-m relationships through specified Modeler</li>
	* </ul>
	* </p>
	* 
	* @example The blog Post belongs-to Author and has-many comments: 
	*  <listing version="3.0">
	*  package example.model {
	*    dynamic class Post extends Modeler {
	*      private static const relations:Relater = new Relater(Post, 
	*        function(me:Relater):void {
	*          me.belongsTo('author', {class_name: 'example.model.Person'});
	*          me.hasMany('comments', {class_name: 'example.model.Comment'});
	*       });
	*    }
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
	* @see Associator
	* @see Modeler
	*  
	**/
	public class Relater
	{
    /**
    * @internal   
    * 
    * Note: The Relater sets association information for its
    * corresponding Modeler sub-class objects by setting the prototype members
 		* on the model class.
		*
		**/		
		private var mKlass:Class = null;		// Modeler being related

    /**
    * Construct a <code>Relater</code> for a given model.
    * 
    * @param klass The <code>Modeler</code> sub-class whose associations to relate.
    * 
    * @param directive A Function taking in the <code>Relater</code> as a 
		* parameter and returning <code>void</code>. Use association methods on 
		* the <code>Relater</code> object to specify relationships.
    * <pre>
    *   function(me:Relater):void {
		*     me.hasMany('things', {class_name: 'some.package.ThingClass'});
    *   }
    * </pre>
    * @see Modeler
    * @see Associator
		* 
    **/		
		public function Relater(klass:Class, directive:Function) {
			mKlass = klass;
			if (!mKlass.prototype.knownAssociations) {
				mKlass.prototype.knownAssociations = new Object();
			}
			directive.call(this, this);
		}
		
		/**
		* Specify has_many relationship.
		* 
		* @param name The name of the association, which becomes available as a
		* property on the Modeler class objects. 
		* 
		* @param options An Object hash of options. Recognized options: 
		* <ul>
		* <li><strong>class_name</strong>: Name of target association class
		* <li><strong>foreign_key</strong>: Foreign key in the target table 
		* which corresponds to relationship with the source model</li>
		* <li><strong>through</strong>: The intermediate association (or join table) 
		* through which this model has_many relationship with a third model. </li>
		* </ul>
		* 
		* class_name is required. There must be a Associator specified corresponding
		* to the through property. This implies the join-table is managed via a 
		* Modeler class. 
		* 
		* If foreign_key options are not specified, they are deduced. 
		*
		* @example A Person has_many friendships through Relationship. This illustrates
		* a self-referential directed many-many association. The Relationship schema 
		* has from_id, to_id and other attribute fields.
		* 
		*  <listing version="3.0">
		*  package example.model {
		*    dynamic class Person extends Modeler {
		*      private static const relations:Relater = new Relater(Post, 
		*        function(me:Relater):void {
		*	         me.hasMany('friendships', {foreign_key: 'from_id', 
	  *              class_name: 'example.model.Relationship'});
		*          me.hasMany('friends', {through: 'friendships', 
		*              foreign_key: 'to_id', class_name: 'example.model.Person'});
		*       });
		*    }
		*  }
		*  </listing>
		* @see DB#mapForeignKey
		* @see Inflector
		* @see Associator 
		* 
		**/
		public function hasMany(name:String, options:Object = null):void {
			associate(Associator.HAS_MANY, name, options);
		}

		/**
		* Specify belongs_to relationship.
		* 
		* @param name The name of the association, which becomes available as a
		* property on the Modeler class objects. 
		* 
		* @param options An Object hash of options. Recognized options: 
		* <ul>
		* <li><strong>class_name</strong>: Name of target association class
		* <li><strong>foreign_key</strong>: Foreign key in the source table 
		* which corresponds to relationship with the target model</li>
		* </ul>
		* 
		* If foreign_key is not specified, it is deduced from model name. 
		*
		* @see DB#mapForeignKey
		* @see Inflector
		* @see Associator 
		* 
		**/		
		public function belongsTo(name:String, options:Object = null):void {
			associate(Associator.BELONGS_TO, name, options);
		}
		
		/**
		* Specify has_and_belongs_to_many relationship.
		* 
		* @param name The name of the association, which becomes available as a
		* property on the Modeler class objects. 
		* 
		* @param options An Object hash of options. Recognized options: 
		* <ul>
		* <li><strong>class_name</strong>: Name of target association class
		* <li><strong>foreign_key</strong>: Foreign key for this model in the
		* join table (whose name is automatically deduced)</li>
		* </ul>
		* 
		* If foreign_key is not specified, it is deduced from model name. 
		*
		* @see DB#mapForeignKey
		* @see DB#mapJoinTable
		* @see Inflector
		* @see Associator 
		* 
		**/		
		public function hasAndBelongsToMany(name:String, options:Object = null):void {
			associate(Associator.HAS_AND_BELONGS_TO_MANY, name, options);
		}
		
		/**
		* Specify a has_one relationship 
		* The foreign_key if specified is the column name within this model schema
		* to access the target model. 
		**/
		public function hasOne(name:String, options:Object = null):void {
			associate(Associator.HAS_ONE, name, options);
		}
		
		private function associate(atype:String, name:String, options:Object):void {
			var assoc:Object = new Object();
			assoc.type = atype;
			assoc.options = options;
			mKlass.prototype.knownAssociations[name] = assoc;
		}		
	}
}