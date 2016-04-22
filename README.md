# Postgres connection manager for R

## rpgmanager package

This package aims to simplify the way you can connect to Postgres databases by using a system of aliases.

After the user has set up a list of aliases corresponding to a set of hostname / port / database / username, this package lets you easily connect to and run queries against that database using the aliases.

It plays well with .pgpass, so if you're using that, it won't ask for your password! 
Working with a .pgpass file is the recommended way to using this package. 

If you're not using .pgpass, you'll be asked for the password when you try to connect a creation to a new database. This will only work in interactive sessions, though.

## Example

After setting up your db.conf like so:

```
#alias:hostname:port:database:user
database1:my.postgres.db.com:5432:my_database1:user1
```

... and your .pgpass like this (optional):
```
#hostname:port:database:username:password
my.postgres.db.com:5432:my_database:user1:my_password
```

You can easily run queries against `database1` in R as shown below:
```R
# Load package
library(rpgmanager)

# Create connection using the alias
db1 <- newConnection("database1")

# Run a text query against database1
res1 <- runQuery(db1, query = "SELECT * FROM users;")

# Run a query from a file against database1
res2 <- runQuery(db1, userFile = TRUE, queryLocation = "~/query2.sql")

# Free up resources taken by the connection
destroyConnection(db1)
```

## Motivation

This R package is for people who run a lot of queries against a lot of different databases. 

This setup lets you easily connect to different databases by using db.conf, a file listing 
connection details (sets of hostname / port / database / username) matched to aliases.

It also lets you keep and manage your own library of SQL queries by taking input SQL files.

## Installation

### Easy install

You can run this code directly in R
```R
# Install devtools
install.packages("devtools")

# Install the package directly from github
devtools::install_github("delormev/r-pg-manager")
```

### Manual install

Clone this repository
```bash
cd my_dir
git clone https://github.com/delormev/r-pg-manager.git
```

And then in R, install the package from the local files
```R
setwd("my_dir")
install.packages("r-pg-manager", repos = NULL, type = "source")
```

## Future improvements

* Output to CSV
* Interactive prompt for password when missing from .pgpass

## Similar projects
[queries.sh](https://github.com/delormev/database-utilities#queriessh), a tool using the same db.conf system and providing the same general functionalities from the command line
