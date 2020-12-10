#!/usr/local/bin/perl -w


# use LWP::UserAgent;
# use Sys::Syslog qw( :DEFAULT setlogsock);
use DBI;
use DBD::mysql;

require '/opt/cc128/login_details.pl';
$|=1;

$serialport = "/dev/ttyUSB0";
$cycletime=60;

# CONFIG VARIABLES

my $socket="/var/run/mysqld/mysqld.sock";

# $feed_id="10840";
# $api="6b292359d1e4abdcc92cc92eb47a59f9b72a3bcee83006f55b64a6759044c24d";

#$VER="v0.1";

$DEBUG=0;

our $dbh; # DB handle as GLOBAL VAR

print "$database : $host\n";

#####################################################################################

sub logit($) {
	my $line = shift;
	print STDERR localtime()." $line\n";
	# setlogsock('unix');
	# openlog($0,'','user');
	# syslog('notice',"$line");
	# closelog;
};
sub dielog($) {
	logit("I died: ".shift);
	die();
};

# sub pachube($$) {

# 	local($temp,$watts)=@_;
	
# 	# 0 = temp, 1=watts
# 	local $data="0,$temp\r\n1,$watts\r\n";

# 	logit("sending to pachube: temp: $temp watts: $watts") if ($DEBUG>0);

# 	my $ua = LWP::UserAgent->new();
# 	#$ua->agent("Mozilla/7.0 - My Pachube Agent $VER");
# 	$ua->agent("Mozilla/7.0");

# 	my $req = HTTP::Request->new( PUT => "http://api.pachube.com/v2/feeds/".$feed_id );
# 	$req->header('X-PachubeApiKey' => $api);
# 	$req->header('content-length' => length($data));
# 	$req->header('content-type' => 'text/plain');

# 	$req->content($data);

# 	my $response = $ua->request($req);

# 	if ($response->is_success) {
# 		logit("sent $data") if ($DEBUG>0);
# 	} else {
#      		logit($response->status_line);
# 	};

# };

sub insertDB($) {

	local $value=shift;

	#
	# setup a mysql timestamp 'YYYY-MM-DD HH:MM:SS'
	#
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
	my $timestamp = sprintf("%4d-%02d-%02d %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);

	#
	# DB insert of data
	#
	my $query = "INSERT INTO cc128 (id,time,value) VALUES (DEFAULT, \'$timestamp\', $value)";

	print "$query\n" if ($DEBUG>0);

	my $sth = $dbh->prepare($query);

	my $retval=$sth->execute();

	if (!$retval) {
		die("INSERT Error on DB : $dbh->errstr()\n");
	};

	# that query has ended
	$sth->finish;

	# add this so we can run a healthcheck on it
	$string="INSERT: $timestamp - $value";
	logit($string);

	# more health checking
	my $filename = '/opt/cc128/heathcheck.log';
	open(FH, '>', $filename) or die $!;
	print FH $string;
	close(FH);
};
#####################################################################################

#my $effectiveUID=$>;
#my $realUID=$<;

#if ($realUID !=0) {
#        logit("Not running as root - exiting...");
#        print "Not running as root - exiting...\n";
#        exit (1);
#};

logit("starting");

my $continue = 1;
$SIG{TERM} = sub { $continue = 0 };

#
# open serial port
# 
eval {
	local $SIG{ALRM} = sub { die("alarm\n"); };
	alarm(10);
	open(SERIAL, "<$serialport") || dielog("Open error: Can't open $serialport because $!");
	alarm(0);
};    
if ($@) {
	if ($@ eq "alarm\n") {
		die ("Serial port open timed out\n");
} else {
		die ("ugh some other error at serial port open : $@ because \"$!\"\n");
	};  
};  

# now set baud rate - VERY IMPORTANT on OSX

#$msg=`stty -f $serialport 57600 2>&1`; # OSX = -f  little 'f'
$msg=`stty -F $serialport 57600 2>&1`; # linux = -F  big 'f'
$ERR=$?;
if ($ERR != 0) {
	dielog("cant set baud on $serialport : $msg");
};

logit("waiting on $serialport err=$ERR");

#
# open DB
#
#my $dsn = "DBI:$platform:$database:$host:$port";
my $dsn = "DBI:mysql:database=$database;host=$host;mysql_socket=$socket";
$dbh = DBI->connect(
	$dsn, $user, $pw,  
	{ RaiseError => 1 } 
	) ||
	die "Database connection not made: $DBI::errstr\n"; 

$oldts=0;
if (!<SERIAL>) {
	print "Serial NOT open\n";
};

#$line=""; 
#while (defined($line = <SERIAL>) && ($continue==1)) { ## daemon loop
my $DEBUG=0;
while (<SERIAL>) { ## daemon loop

	my $line=$_;

	$timestamp=time();

	if ( -e "/opt/cc128/debug.cc128" ) {
		logit($line);
		$DEBUG=1;
	};

	if ($line =~ m!<tmpr>\s*(-*[\d.]+)</tmpr>.*<ch1><watts>(\d+)</watts></ch1>!) {
		$watts = $2;
		$temperature = $1;
		logit("DEBUG: $timestamp reading watts:$watts temp:$temperature"); #if ($DEBUG==1); #see debug.cc128 above

		push @arr_watts, $watts;	
	};

	if ($timestamp-$oldts > $cycletime) {
		$oldts=$timestamp;

		my $sum=0;
		my $avg=0;
		my $count = scalar @arr_watts;
		if ($count>0) {
			foreach (@arr_watts) { $sum += $_; }
			$avg = $sum / $count ;
		};

		@arr_watts=();
		
		#send it
		insertDB($avg);	
		#pachube($temperature,$avg);
	};

}; ## daemon loop
close(SERIAL);

$dbh->disconnect or warn "Disconnection failed: $!\n";

logit("Exiting cleanly...");

exit 0;


