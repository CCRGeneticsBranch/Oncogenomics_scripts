use DBI;
use Time::Piece;
use Getopt::Long qw(GetOptions);


sub getDBI {
  my ($host, $sid, $username, $passwd, $port) = getDBConfig();  
  my $dbh = DBI->connect( "dbi:Oracle:host=$host;port=$port;sid=$sid", $username, $passwd, {
      AutoCommit => 0,
      RaiseError => 1,    
  }) || die( $DBI::errstr . "\n" );
  return $dbh;
}

sub getDBHost {
  my ($host, $sid, $username, $passwd, $port) = getDBConfig();
  return $host;
}

sub getDBSID {
  my ($host, $sid, $username, $passwd, $port) = getDBConfig();
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
  my $script_dir = dirname(__FILE__);
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
  my $script_dir = dirname(__FILE__);
  my $config_refs = _getConfig("$script_dir/../../../.env");
  my %configs = %$config_refs;
  my $host = "";
  my $sid = "";
  my $username = "";
  my $passwd = "";
  my $port="";
  foreach $key (keys %configs) {
        my $value = $configs{$key};
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
        if ($host ne "" && $sid ne "" && $username ne "" && $passwd ne "" && $port ne "") {
          return ($host, $sid, $username, $passwd, $port);
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