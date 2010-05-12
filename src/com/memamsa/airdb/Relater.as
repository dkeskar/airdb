package com.memamsa.airdb
{
	public class Relater
	{
		private var mKlass:Class = null;		// Modeler being related
		
		public function Relater(klass:Class, directive:Function) {
			mKlass = klass;
			if (!mKlass.prototype.knownAssociations) {
				mKlass.prototype.knownAssociations = new Object();
			}
			directive.call(this, this);
		}
		
		public function hasMany(name:String, options:Object = null):void {
			associate(Associator.HAS_MANY, name, options);
		}
		
		public function belongsTo(name:String, options:Object = null):void {
			associate(Associator.BELONGS_TO, name, options);
		}
		
		public function hasAndBelongsToMany(name:String, options:Object = null):void {
			associate(Associator.HAS_AND_BELONGS_TO_MANY, name, options);
		}
		
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