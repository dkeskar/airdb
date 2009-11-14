package example
{
  import com.memamsa.airdb.DB;
  import com.memamsa.airdb.Migrator;
  import com.memamsa.airdb.Modeler;
  
  [Association(type="has_and_belongs_to_many", name="comments", className="example.Comment")]
  
  dynamic public class Post extends Modeler
  {
    private static const migrations:Migrator = new Migrator(
      Post,
      {id: true},
      [
        function(my:Migrator):void {
          my.createTable(function():void {
            my.column('title', DB.Field.VarChar, {limit: 128});
            my.column('author', DB.Field.VarChar, {limit: 40});
            my.columnTimestamps();
          });
        },
        // Here is how you add a new migration directive as an element of the array 
        function(my:Migrator):void {
		  my.joinTable(Comment);
		}
      ]);
      // other class methods and properties
  }
}