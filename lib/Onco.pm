use DBI;
use Time::Piece;
use Getopt::Long qw(GetOptions);


sub getDBI {
  my ($db_type, $host, $sid, $username, $passwd, $port) = getDBConfig();
  my $dbh;
  print "db_type: $db_type\n";
  if ($db_type eq "oracle") {  
    $dbh = DBI->connect( "dbi:Oracle:host=$host;port=$port;sid=$sid", $username, $passwd, {
      AutoCommit => 0,
      RaiseError => 1,    
    }) || die sprintf( 'connect() failed. Error: %s', DBI->errstr);
  }
  if ($db_type eq "mysql") {  
    $dbh = DBI->connect( "dbi:mysql:$sid:$host", $username, $passwd, {
      AutoCommit => 0,
      RaiseError => 1,    
    }) || die( $DBI::errstr . "\n" );
  }
  return $dbh;
}

sub getDBHost {
  my ($db_type, $host, $sid, $username, $passwd, $port) = getDBConfig();
  return $host;
}

sub getDBType {
  my ($db_type, $host, $sid, $username, $passwd, $port) = getDBConfig();
  return $db_type;
}

sub getDBSID {
  my ($db_type, $host, $sid, $username, $passwd, $port) = getDBConfig();
  return $sid;
}

sub print_log {
    my ($msg) = @_;
    #open CMD_FILE, ">>$cmd_log_file" || print "cannot create command log file";
    #print CMD_FILE "[".localtime->strftime('%Y-%m-%d %H:%M:%S')."] $msg\n";
    #close(CMD_FILE);
    $msg = "[".localtime->strftime('%Y-%m-%d %H:%M:%S')."] $msg\n";
    print "$msg";
}

sub getConfig {
  my ($key) = @_;
  if ($ENV{$key}) {
    return $ENV{$key};
  }

  my $script_dir = dirname(__FILE__);
  #print("using env file: $script_dir/../../../.env");
  my $config_refs = _getConfig("$script_dir/../../../.env");
  my %configs = %$config_refs;
  foreach $_key (keys %configs) {
    if ($key eq $_key) {
      return $configs{$key};
    }
  }
  return ""; 
}

sub formatDir {
    my ($dir) = @_;
    if ($dir !~ /\/$/) {
        $dir = $dir."/";
    }
    return $dir;
}

sub getDBConfig {
  if ($ENV{DB_CONNECTION} && $ENV{DB_HOST} && $ENV{DB_DATABASE} && $ENV{DB_USERNAME} && $ENV{DB_PASSWORD} && $ENV{DB_PORT}) {
    return ($ENV{DB_CONNECTION}, $ENV{DB_HOST}, $ENV{DB_DATABASE},$ENV{DB_USERNAME},$ENV{DB_PASSWORD},$ENV{DB_PORT});
  }
  my $script_dir = dirname(__FILE__);
  my $config_refs = _getConfig("$script_dir/../../../.env");
  my %configs = %$config_refs;
  my $dbtype = "";
  my $host = "";
  my $sid = "";
  my $username = "";
  my $passwd = "";
  my $port="";
  foreach $key (keys %configs) {
        my $value = $configs{$key};
        if ($key eq "DB_CONNECTION") {
          $db_type = $value;
        }
        if ($key eq "DB_HOST") {
          $host = $value;
        }
        if ($key eq "DB_DATABASE") {
          $sid = $value;
        }
        if ($key eq "DB_USERNAME") {
          $username = $value;
        }
        if ($key eq "DB_PASSWORD") {
          $passwd = $value;
        }
        if ($key eq "DB_PORT") {
          $port = $value;
        }
        if ($db_type ne "" && $host ne "" && $sid ne "" && $username ne "" && $passwd ne "" && $port ne "") {
          return ($db_type, $host, $sid, $username, $passwd, $port);
        }   
  }
  return ();  
}

sub _getConfig {
  my ($file) = @_;
  open(FILE, "$file") or die "Cannot open file $file";
  my %configs = ();
  while (<FILE>) {
    chomp;
    if (/(.*)=(.*)$/) {
      my $key = $1;
      my $value = $2;
      $key =~ s/[\s\'\"]//g;
      $value =~ s/[\s\'\"]//g;
      $configs{$key} = $value;      
    }    
  }
  close(FILE);
  return \%configs;
}
1;