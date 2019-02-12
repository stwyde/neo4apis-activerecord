# neo4apis-activerecord

**The easiest and quickest way to copy data from PostgreSQL / mySQL / sqlite to Neo4j**

## How to run:

Without existing ActiveRecord application:

    neo4apis activerecord all_tables --identify-model --import-all-associations

or

    neo4apis activerecord tables posts comments --identify-model --import-all-associations

With existing ActiveRecord application:

    neo4apis activerecord all_models --import-all-associations

or

    neo4apis activerecord models Post Comment --import-all-associations

## Additional run time options for ActiveRecord Applications:

With an existing ActiveRecord application, a few new options are also available.

    neo4apis activerecord all_models_except Comment --import-all-associations

Will import all models in your ActiveRecord application unless that model is part of the exceptions list. In the case of polymorphic association, the blacklisted model will be included in the initial query, but skipped once the import script checks its type and notices that it is blacklisted. 

You can also try: 

    neo4apis activerecord models_with_internal_associations Post Comment --import-all-associations

This will only import models that you've also mentioned. For example, if there's a relationship between Posts and a User (say User has many Posts, Post belongs to User), the "models Post Comment" import will also grab users that a given Post belongs to and import them as well. The "models_with_internal_associations" import method checks to make sure that any model not explicitly mentioned is not imported. 

Lastly (PENDING IMPLEMENTATION TODO BEFORE PULL REQUEST), you can specify both models you're interested in, as well as a blacklist. Say you wanted to import Posts, Users, anything associated with Users, but not Comments made by Users or attached to Posts? 

    neo4apis activerecord models_named Post User except Comment --import-all-associations

This call will skip Comments whenever encountered during import while importing the rest of the associations found. 

## Installation

Using rubygems:

    gem install neo4apis-activerecord

## How it works

[ActiveRecord](http://guides.rubyonrails.org/active_record_basics.html) is a [ORM](http://en.wikipedia.org/wiki/Object-relational_mapping) for ruby.  `neo4apis-activerecord` uses ActiveRecord models which are either found in an existing ruby app or generated from table structures.  The models are then introspected to create nodes (from tables) and relationships (from associations) in neo4j.  The neo4apis library is used to load data efficiently in batches.

## Options

For a list of all options run:

    neo4apis activerecord --help

Some options of particular interest:

### `--identify-model`

The `--identify-model` option looks for tables' names/primay keys/foreign keys automatically.  Potential options are generated and the database is examined to find out which fits.

As an example: for a table of posts the following possibilities would checked:

 * Names: Looks for names like `posts`, `post`, `Posts`, or `Post`
 * Primary keys: Table schema is examined first.  If no primary key is specified it will look for columns like `id`, `post_id`, `PostId`, or `uuid`
 * Foreign keys: `author_id` or `AuthorId` will be assumed to go to a table of authors (with a name identified as above)

### `--import-belongs-to`
### `--import-has-many`
### `--import-has-one`
### `--import-has-and-belongs-to-many`
### `--import-all-associations`

Either specify that a certain class of associations be imported from ActiveRecord models or specify all with `--import-all-associations`

## Using `neo4apis-activerecord` from ruby

If you'd like to do custom importing, you can use `neo4apis-activerecord` in the following way:

    Neo4Apis::ActiveRecord.model_importer(SomeModel)

    neo4apis_activerecord = Neo4Apis::ActiveRecord.new(Neo4j::Session.open, import_all_associations: true)

    neo4apis_activerecord.batch do
      SomeModel.where(condition: 'value').find_each do |object|
        neo4apis_activerecord.import object
      end
    end

