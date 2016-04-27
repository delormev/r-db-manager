# R Postgres Manager

setClass("DatabaseConnectionManager", slots = c(connection="DBIConnection", driver="DBIDriver"))

#' Easy connection to a Postgres database using aliases
#'
#' Creates a PostgreSQL driver and a connection to the database \code{dbAlias}
#' using the .pgpass and db.conf files specified.
#' 
#' The db.conf file is defined one alias per line. Each alias is defined using this format:
#' \code{#alias:hostname:port:database:username}
#' \code{database1:my.postgres.db.com:5432:my_database1:user1}
#' @param dbAlias alias of the database you want to connect to (must be present in db.conf)
#' @param pgPassFile location of ".pgpass" on your filesystem (optional; defaults to "~/.pgpass")
#' @param dbConfFile location of "db.conf" on your filesystem (optional; defaults to "~/db.conf")
#' @return PostgresConnectionManager object including a PostgreSQLDriver and a PostgresSQLConnection 
#'          to the database in question
#' @seealso \code{\link{runQuery}}, \code{\link{destroyConnection}} 
#' @export
#' @examples
#' newConnection("my_db")
#' newConnection("my_db", dbConfFile = "/path/to/your/db.conf")
newConnection <- function(dbAlias, pgPassFile = "~/.pgpass", dbConfFile = "~/db.conf") {
  # Creates a PostgreSQL driver and a connection to the database `dbAlias`
  # using the pgpass and db.conf files specified.
  #
  # Args:
  #   dbAlias: Alias of the database you want to connect to (must be
  #            present in db.conf)
  #   pgPassFilex: Location of ".pgpass" on your filesystem.
  #   dbConfFile: Location of "db.conf" on your filesystem.
  #
  # Returns:
  #   A PostgresConnectionManager including a PostgreSQLDriver and a PostgresSQLConnection to the database in question.
  
  processFileRegex <- function(filename, regex, names) {
    # Create data frame based on the data from `filename`. Filters out anything that doesn't match the 
    # regex. Capturing groups define the columns of the data frame.
    # 
    # Args:
    #   filename: Location of the file to be processed.
    #   regex: Regular expression to process the file with
    #   header: if TRUE, first row is used as column names and removed from the data frame.
    #           Defaults to TRUE.
    #   silent: if TRUE, won't output the logs / reminders after running. Defaults to FALSE.
    # 
    # Returns:
    #   A data frame corresponding to the data from filename matching the regex, broken down in colums.
    rawFile <- readLines(filename)
    rawClean <- rawFile[grep(regex, rawFile)]
    rawFrame <- as.data.frame(str_match(rawClean, regex), stringsAsFactors = FALSE)[,-1]
    colnames(rawFrame) <- names
    return(rawFrame)
  }
  
  # Parses passwords aliases files
  if (file.exists(pgPassFile)) {
    dbPass <- processFileRegex(pgPassFile, "^([^#][^:]*):([^:]*):([^:]*):([^:]*):(.*)$", c("hostname", "port", "database", "username", "password"))
  } else {
    dbPass <-  read.table(text = "",
                      col.names = c("hostname", "port", "database", "username", "password"),
                      stringsAsFactors=FALSE)
  }
  dbConf <- processFileRegex(dbConfFile, "^([^#][^:]*):(mysql|postgres):([^:]*):([^:]*):([^:]*):([^\\[]*)(?:.*)$", c("alias", "dbtype", "hostname", "port", "database", "username"))
  
  # Merges the files, also accounts for potential "*" in db
  dbMerged <- merge(x=dbPass, y=dbConf, by=c("hostname", "username", "port"), all.y=TRUE)
  dbMerged <- dbMerged[(dbMerged$database.x == "*") || (is.na(dbMerged$database.x)) || (dbMerged$database.x == dbMerged$database.y), !(names(dbMerged) == "database.x")]
  names(dbMerged)[names(dbMerged) == "database.y"] <- "database"
  
  dbInfo <- subset(dbMerged, dbMerged$alias == dbAlias)
  if (nrow(dbInfo) == 0) stop("Alias provided not found in db.conf")
  if (nrow(dbInfo) > 1) stop("Error looking up the alias provided in db.conf")
  if (is.na(dbInfo$password) && interactive()) {
    cat("No password found for database ", dbAlias, ".\n", sep="")
    dbInfo$password <- readline(prompt=paste("Password for alias ", dbAlias, ": ",  sep=""))
  }
  
  if (dbInfo$dbtype == "postgres") {
    drv <- dbDriver("PostgreSQL")
  } else {
    drv <- dbDriver("MySQL")
  }
  con <- dbConnect(drv,
                   host=dbInfo$hostname,
                   dbname=dbInfo$database,
                   user=dbInfo$username,
                   port=as.integer(dbInfo$port),
                   password=dbInfo$password)
  
  pgObjects <- new("DatabaseConnectionManager", 
                   driver = drv, 
                   connection = con)
  
  return(pgObjects)
}

#' Clears up the resources used by a PostgresConnectionManager
#'
#' Clears up resources by disconnecting all the connections to the driver, 
#' then unloading the driver
#' @param dbManager PostgresConnectionManager object to run the query against
#' @return Nothing. Side-effects only. 
#' @seealso \code{\link{newConnection}}, \code{\link{runQuery}}
#' @export
#' @examples
#' destroyConnection(pgManager)
destroyConnection <- function(dbManager) {
  # Clears up the resources used by a PostgresConnectionManager object by disconnecting all the connections
  # to the driver, then unloading the driver.
  #
  # Args:
  #   pgManager: A PostgresConnectionManager object
  #
  # Returns:
  #   Nothing. Side-effects only. 
  if (!(class(dbManager) == "DatabaseConnectionManager" && typeof(dbManager) == "S4")) stop("Parameter should be an instance of DatabaseConnectionManager")
  for (conn in dbListConnections(dbManager@driver)) { 
    dbDisconnect(conn)
  }
  dbUnloadDriver(dbManager@driver)
}

#' Run a query against a PostgresConnectionManager object
#'
#' Runs a query against the specified PostgresConnectionManager object, either by specifying the SQL directly or 
#'pointing at a file containing the query.
#' @param pgManager PostgresConnectionManager object to run the query against
#' @param query a string containing query to run against the connection (optional; needed if useFile = FALSE)
#' @param useFile a boolean indicating whether to run a query directly or run the query from file (optional; defaults to FALSE)
#'   If TRUE, queryLocation must be present and pointing to an existing file.
#'   If FALSE, query must be specified.
#' @param queryLocation a string pointing at the location of the query file (optional; needed if useFile = TRUE)
#' @return The resulting data frame
#' @seealso \code{\link{newConnection}}, \code{\link{destroyConnection}} 
#' @export
#' @examples
#' runQuery(pgManager, "SELECT * FROM users;")
#' runQuery(pgManager, useFile = TRUE, queryLocation = "~/query.sql")
runQuery <- function(pgManager, query = "", useFile = FALSE, queryLocation = "") {
  # Runs a query against the specified PostgresConnectionManager object, either by specifying the SQL directly or 
  # pointing at a file containing the query.
  #
  # Args:
  #   pgManager: A PostgresConnectionManager object
  #   query: The query to run against the connection (as a string)
  #   useFile: A boolean indicating whether to run a query directly or run the query from file.
  #             If TRUE, queryLocation must be present and pointing to an existing file.
  #             If FALSE, query must be specified.
  #   queryLocation: Location of the query file on your filesystem.
  #
  # Returns:
  #    The resulting data frame.
  if (!(class(pgManager) == "DatabaseConnectionManager" && typeof(pgManager) == "S4")) stop("Parameter should be an instance of DatabaseConnectionManager")
  if (useFile && !file.exists(queryLocation)) stop("Specified query file doesn't exist")
  if (useFile) {
    query <- readChar(queryLocation,nchar = file.info(queryLocation)$size)
  }
  return(dbGetQuery(pgManager@connection, query))
}
