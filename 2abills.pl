#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

  to ABillS migrations

   FreeNIBS
   Mabill
   UTM4
   UTM5 (mysql, Postgres)
   Mikbill
   Stragazer
   Nodeny
   Traffpro
   Lanbiling
   Easyhotspot
   Unisys
   BBilling
   Carbonsoft 4

   2abills.pl former abills migration file for Cards module account creation

=cut

use DBI;
use strict;
use vars qw( %conf );
use FindBin '$Bin';

my $ARGUMENTS = parse_arguments(\@ARGV);
my $VERSION   = 0.72;

#DB information

my $dbhost   = $ARGUMENTS->{DB_HOST}     || "127.0.0.1";
my $dbname   = $ARGUMENTS->{DB_NAME}     || "abills";
my $dbuser   = $ARGUMENTS->{DB_USER}     || "root";
my $dbpasswd = $ARGUMENTS->{DB_PASSWORD} || "";
my $dbtype   = $ARGUMENTS->{DB_TYPE}     || "mysql";       #Pg
my $encryption_key = $ARGUMENTS->{PASSSWD_ENCRYPTION_KEY};

if (defined($ARGUMENTS->{'help'}) || $#ARGV < 0) {
  help();
  exit 0;
}

my $IMPORT_FILE      = $ARGUMENTS->{IMPORT_FILE}      || '';
my $FILE_FIELDS      = $ARGUMENTS->{FILE_FIELDS}      || '';
my $DEFAULT_PASSWORD = $ARGUMENTS->{DEFAULT_PASSWORD} || 'xxxx';
my $email_export     = $ARGUMENTS->{EMAIL_CREATE}     || 1; #FIXME : missing functions
my $EMAIL_DOMAIN_ID  = $ARGUMENTS->{EMAIL_DOMAIN}     || 1;
my $DEBUG            = $ARGUMENTS->{DEBUG}            || 0;
my $no_deposit       = $ARGUMENTS->{NO_DEPOSIT}       || 0; #FIXME : missing functions
my $EXCHANGE_RATE    = $ARGUMENTS->{EXCHANGE_RATE}    || 0;
my $FORMAT = ($ARGUMENTS->{'HTML'}) ? 'html' : '';
my $SYNC_DEPOSIT = $ARGUMENTS->{SYNC_DEPOSIT} || 0;

my %EXTENDED_STATIC_FIELDS = ();

while (my ($k, $v) = each(%$ARGUMENTS)) {
  if ($k =~ /^(\d)\./) {
    $EXTENDED_STATIC_FIELDS{$k} = $v;
    print "Extended: $k -> $v\n" if ($DEBUG > 1);
  }
}

my DBI $db;

if ($ARGUMENTS->{ADD_NAS}) {
  add_nas();
  exit;
}

if ($ARGUMENTS->{FROM}) {
  if ($ARGUMENTS->{FROM} eq 'stargazer_pg') {
    $dbtype = 'Pg';
  }
  elsif ($ARGUMENTS->{FROM} eq 'odbc' || $ARGUMENTS->{FROM} eq 'carbon4') {
    $dbtype = 'ODBC';
    my $db_dsn = 'MSSQL';

    eval { require DBD::ODBC; };
    if (@!) {
      print "Please install 'DBD::ODBC'\n";
      print "Manual: http://abills.net.ua/wiki/doku.php/abills:docs:manual:soft:perl_odbc \n";
      exit;
    }
    DBD::ODBC->import();

    if ($ARGUMENTS->{FROM} eq 'carbon4') {
      $db = get_connection_to_firebird_host($dbhost, '/var/db/ics_main.gdb', $dbpasswd);
    }
    else {
      $db = DBI->connect("dbi:ODBC:DSN=$db_dsn;UID=$dbuser;PWD=$dbpasswd")
      or die "Unable connect to server '$dbtype:dbname=$dbname;host=$dbhost'\n user: $dbuser \n password: $dbpasswd \n$!\n" . ' dbname: ' . $dbname . ' dbuser: ' . $dbuser . ' dbpassword - ' . $dbpasswd . "\n" . $DBI::errstr . "\n" . $DBI::state . "\n" . $DBI::err . "\n" . $DBI::rows;
    }

  }
  else {
    $db = DBI->connect("dbi:$dbtype:dbname=$dbname;host=$dbhost", "$dbuser", "$dbpasswd")
    || die "Unable connect to server '$dbtype:dbname=$dbname;host=$dbhost'\n user: $dbuser \n password: $dbpasswd \n$!\n" . ' dbname: ' . $dbname . ' dbuser: ' . $dbuser . ' dbpassword - ' . $dbpasswd . "\n" . $DBI::errstr . "\n" . $DBI::state . "\n" . $DBI::err . "\n" . $DBI::rows;
  }
}

if ($ARGUMENTS->{DB_CHARSET}) {
  $db->do("set names $ARGUMENTS->{DB_CHARSET}");
}

#Tarif migration section
my %TP_MIGRATION = ();
if ($ARGUMENTS->{TP_MIGRATION}) {
  my $rows = file_content($ARGUMENTS->{TP_MIGRATION});

  foreach my $line (@$rows) {
    my ($old, $new) = split(/=/, $line, 2);
    $TP_MIGRATION{$old} = $new;
  }
}

my $INFO_LOGINS;

if ($ARGUMENTS->{FROM}) {
  if ($ARGUMENTS->{FROM} eq 'freenibs') {
    $INFO_LOGINS = get_freenibs_users();
  }
  elsif ($ARGUMENTS->{FROM} eq 'mabill') {
    $INFO_LOGINS = get_freenibs_users({ MABILL => 1 });
  }
  elsif ($ARGUMENTS->{FROM} eq 'utm4') {
    $INFO_LOGINS = get_utm4_users();
  }
  elsif ($ARGUMENTS->{FROM} eq 'utm5') {
    $INFO_LOGINS = get_utm5_users();
  }
  elsif ($ARGUMENTS->{FROM} eq 'utm5cards') {
    utm5cards();
    exit;
  }
  elsif ($ARGUMENTS->{FROM} eq 'utm5pg') {
    $INFO_LOGINS = get_utm5pg_users();
  }
  elsif ($ARGUMENTS->{FROM} eq 'unisys') {
    $INFO_LOGINS = get_unisys();
  }
  elsif ($ARGUMENTS->{FROM} eq 'file') {
    if ($SYNC_DEPOSIT) {
      $FILE_FIELDS = 'LOGIN,NEW_SUM';
      $IMPORT_FILE = $SYNC_DEPOSIT;
      $INFO_LOGINS = get_file();
      sync_deposit($INFO_LOGINS);
      exit 0;
    }
    else {
      $INFO_LOGINS = get_file();
    }
  }
  elsif ($ARGUMENTS->{FROM} eq 'abills') {
    $INFO_LOGINS = get_abills();
  }
  elsif ($ARGUMENTS->{FROM} eq 'mikbill') {
    $INFO_LOGINS = get_mikbill();
  }
  elsif ($ARGUMENTS->{FROM} eq 'mikbill_deleted') {
    $INFO_LOGINS = get_mikbill_deleted();
  }
  elsif ($ARGUMENTS->{FROM} eq 'mikbill_blocked') {
    $INFO_LOGINS = get_mikbill_blocked();
  }
  elsif ($ARGUMENTS->{FROM} eq 'nodeny') {
    $INFO_LOGINS = get_nodeny();
  }
  elsif ($ARGUMENTS->{FROM} eq 'traffpro') {
    $INFO_LOGINS = get_traffpro();
  }
  elsif ($ARGUMENTS->{FROM} eq 'stargazer') {
    $INFO_LOGINS = get_stargazer();
  }
  elsif ($ARGUMENTS->{FROM} eq 'stargazer_pg') {
    $INFO_LOGINS = get_stargazer_pg();
  }
  elsif ($ARGUMENTS->{FROM} eq 'easyhotspot') {
    $INFO_LOGINS = get_easyhotspot();
  }
  elsif ($ARGUMENTS->{FROM} eq 'bbilling') {
    $INFO_LOGINS = get_bbilling();
  }
  elsif ($ARGUMENTS->{FROM} eq 'lms') {
    $INFO_LOGINS = get_lms();
  }
  elsif ($ARGUMENTS->{FROM} eq 'lms_nodes') {
    $INFO_LOGINS = get_lms_nodes();
  }
  elsif ($ARGUMENTS->{FROM} eq 'odbc') {
    $INFO_LOGINS = get_odbc();
  }
  elsif ($ARGUMENTS->{FROM} eq 'carbon4') {
    $INFO_LOGINS = get_carbon4();
  }

  show($INFO_LOGINS);
}

if ($db) {
  $db->disconnect();
  $db = undef;
}

#**************************************************
# ADD_NAS=file FIELDS=NAS_NAME,MAC
#
#Felds:
# NAS_NAME
# IP
# MAC
# NAS_IDENTIFIER
# NAS_DESCRIBE
# NAS_AUTH_TYPE
# NAS_MNG_IP_PORT
# NAS_MNG_USER
# NAS_MNG_PASSWORD
# NAS_RAD_PAIRS
# NAS_ALIVE
# NAS_DISABLE
# NAS_EXT_ACCT
#
#**************************************************
sub add_nas {
  my ($attr) = @_;

  if (!$FILE_FIELDS) {
    print "Specify fields FILE_FIELDS=... \n";
    exit;
  }

  $FILE_FIELDS =~ s/\s//g;
  my @fiealds_arr = split(/,/, $FILE_FIELDS);

  my $arr          = file_content($ARGUMENTS->{ADD_NAS});
  my @add_arr_hash = ();

  foreach my $line (@$arr) {
    print "$line\n" if ($DEBUG > 3);
    my @val_arr = split(/\t/, $line);

    my %val_hash = ();
    for (my $i = 0 ; $i <= $#val_arr ; $i++) {
      $val_hash{ $fiealds_arr[$i] } = $val_arr[$i];
    }

    push @add_arr_hash, \%val_hash;
  }

  do "/usr/abills/libexec/config.pl";

  unshift(@INC, $Bin . '/../', $Bin . '/../Abills', $Bin . "/../Abills/$conf{dbtype}");

  require Abills::SQL;
  Abills::SQL->import();

  require Nas;
  Nas->import();

  require Admins;
  Admins->import();

  require Dhcphosts;
  Dhcphosts->import();

  if ($DEBUG > 3) {
    print "DB info:
     dbtype: $conf{dbtype}
     dbhost: $conf{dbhost}
     dbname: $conf{dbname}
     dbuser: $conf{dbuser}
     dbpasswd: $conf{dbpasswd}
    ";
  }

  my $abills_db = Abills::SQL->connect($conf{dbtype}, $conf{dbhost}, $conf{dbname}, $conf{dbuser}, $conf{dbpasswd}, { CHARSET => ($conf{dbcharset}) ? $conf{dbcharset} : undef });

  my $admin = Admins->new($abills_db, \%conf);
  $admin->info($conf{SYSTEM_ADMIN_ID}, { IP => '127.0.0.1' });
  my $Dhcphosts = Dhcphosts->new($abills_db, $admin, \%conf);
  $admin->{MODULE} = '';
  my $Nas = Nas->new($abills_db, \%conf);

  if ($DEBUG > 5) {
    return 0;
  }
  elsif ($DEBUG > 2) {
    $Nas->{debug} = 1;
  }

  for (my $i = 0 ; $i <= $#add_arr_hash ; $i++) {
    if ($DEBUG > 2) {
      print "$i - ";
      for (my $if = 0 ; $if <= $#fiealds_arr ; $if++) {
        print "$fiealds_arr[$if]:$add_arr_hash[$i]->{$fiealds_arr[$if]}  ";
      }
      print "\n";
    }

    if ($add_arr_hash[$i]->{MAC}) {
      $add_arr_hash[$i]->{MAC} = mac_former($add_arr_hash[$i]->{MAC});
    }

    $Nas->list({ NAS_IP => $add_arr_hash[$i]->{NAS_IP} || '0.0.0.0' });
    if ($Nas->{TOTAL}) {
      print "Exist add nas_identifier\n" if ($DEBUG > 3);
      $add_arr_hash[$i]->{NAS_IDENTIFIER} = 'NAS_' . +($Nas->{TOTAL} + 1);
    }

    $Nas->list($add_arr_hash[$i]);
    if ($Nas->{TOTAL}) {
      print "Skip: $fiealds_arr[0]:$add_arr_hash[$i]->{$fiealds_arr[0]} \n";
      next;
    }

    $Nas->add($add_arr_hash[$i]);
    if ($Nas->{errno}) {
      print "[$Nas->{errno}] $Nas->{errstr}\n";
      exit;
    }
  }

}

#**********************************************************
#
#**********************************************************
sub mac_former {
  my ($mac) = @_;

  if (!$mac) {
    $mac = '00:00:00:00:00:00';
  }
  elsif ($mac =~ m/([0-9a-f]{2})([0-9a-f]{2})\.([0-9a-f]{2})([0-9a-f]{2})\.([0-9a-f]{2})([0-9a-f]{2})/i) {
    $mac = "$1:$2:$3:$4:$5:$6";
  }
  elsif ($mac =~ m/^([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i) {
    $mac = "00:$1:$2:$3:$4:$5";
  }
  elsif ($mac =~ m/([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})/i) {
    $mac = "$1:$2:$3:$4:$5:$6";
  }
  elsif ($mac =~ s/[\.\-]/:/g) {

  }

  return $mac;
}

#**************************************************
#
#**************************************************
sub file_content {
  my ($filename) = @_;

  my $content = '';

  open(my $fh, "$filename") || die "Can't open file '$filename' $! \n";
  while (<$fh>) {
    $content .= $_;
  }
  close($fh);

  my @arr = split(/[\r]?\n/, $content);

  return \@arr;
}

#**********************************************************

=head2 get_connection_to_firebird_host($server, $db_name, $password) - connect to remote Firebird DB

=cut

#**********************************************************
sub get_connection_to_firebird_host {
  my ($server, $db_name, $password) = @_;

  my $driver = "libOdbcFb.so";    # имя ODBC драйвера, скачан с официального сайта Firebird
  my $user   = "sysdba";          # логин

  my %DSN = (
    ODBC => {
      dsn     => "Driver={$driver};DBNAME=$server:$db_name;uid=$user;pwd=$password",
      heading => 'Using ODBC Driver Manager via DBI::ODBC',
      mode    => 'ODBC',
    }
  );
  my $connect = "dbi:$DSN{ODBC}{'mode'}(RaiseError=>0, PrintError=>1, Taint=>0):$DSN{ODBC}{'dsn'}";

  #  print "Connect string : " . $connect . "\n";
  my $dbhandler = DBI->connect($connect, { PrintError => 1, AutoCommit => 0, ReadOnly => 1 }) || die("Can't connect: $DBI::errstr");

  $dbhandler->{LongReadLen} = 512 * 1024;
  $dbhandler->{LongTruncOk} = 1;

  return $dbhandler;
}

#**************************************************
#
#**************************************************
sub get_abills {
  my ($attr) = @_;

  my %fields = (

    #DECODE(u.password, 'test12345678901234567890') AS password,
    #pi.fio as fio,
    #if(company.id IS NULL,b.deposit,cb.deposit) AS deposit,
    #if(u.company_id=0, u.credit, if (u.credit=0, company.credit, u.credit)) AS credit,
    #u.disable as disable,
    #u.company_id as company_id,
    #u.activate,
    #u.expire,
    #pi.phone,
    #pi.email,
    #pi.country_id,
    #pi.address_street,
    #pi.address_build,
    #pi.address_flat,
    #pi.comments,
    #pi.contract_id,
    #pi.contract_date,
    #pi.contract_sufix,
    #pi.pasport_num,
    #pi.pasport_date,
    #pi.pasport_grant,
    #pi.zip,
    #pi.city,
    #dv.tp_id,
    #INET_NTOA(dv.ip) AS ip,
    #dv.CID,
    #u.reduction,
    #u.gid,
    #u.registration,
    #pi.comments

    'LOGIN'            => 'id',
    'PASSWORD'         => 'password',
    '1.ACTIVATE'       => 'activate',
    '1.EXPIRE'         => 'expire',
    '1.COMPANY_ID'     => 'company_id',
    '1.CREDIT'         => 'credit',
    '1.GID'            => 'gid',
    '1.REDUCTION'      => 'reduction',
    '1.REGISTRATION'   => 'registration',
    '1.DISABLE'        => 'disable',
    '3.ADDRESS_FLAT'   => 'address_flat',
    '3.ADDRESS_STREET' => 'address_street',
    '3.ADDRESS_BUILD'  => 'address_build',
    '3.COUNTRY_ID'     => 'country_id',
    '3.COMMENTS'       => 'comments',
    '3.CONTRACT_ID'    => 'contract_id',
    '3.CONTRACT_DATE'  => 'contract_date',
    '3.CONTRACT_SUFIX' => 'contract_sufix',
    '3.EMAIL'          => 'email',
    '3.FIO'            => 'fio',
    '3.PHONE'          => 'phone',
    '3.ZIP'            => 'zip',
    '3.PHONE'          => 'phone',
    '3.CITY'           => 'city',
    '3.PASSPORT_NUM'   => 'pasport_num',
    '3.PASSPORT_DATE'  => 'pasport_date',
    '3.PASSPORT_GRANT' => 'pasport_grant',

    '4.CID'       => 'CID',
    '4.FILTER_ID' => 'filter_id',
    '4.IP'        => 'ip',

    #  '4.NETMASK'        => '\'255.255.255.255\'',
    #  '4.SIMULTANEONSLY' => 'simultaneous_use',
    #  '4.SPEED'          => 'speed',
    '4.TP_ID' => 'tp_id',

    #  '4.CALLBACK'       => 'allow_callback',

    '5.SUM'      => 'deposit',
    '5.DESCRIBE' => "'Migration'",

    #  '5.ER'             => undef,
    #  '5.EXT_ID'         => undef,

    #  '6.USERNAME'       => 'email',
    #  '6.DOMAINS_SEL'     => $email_domain_id || 0,
    #  '6.COMMENTS'        => '',
    #  '6.MAILS_LIMIT'	    => 0,
    #  '6.BOX_SIZE'	      => 0,
    #  '6.ANTIVIRUS'	      => 0,
    #  '6.ANTISPAM'	      => 0,
    #  '6.DISABLE'	        => 0,
    #  '6.EXPIRE'	        => undef,
    #  '6.PASSWORD'	      => 'email_pass',
  );

  my %fields_rev = reverse(%fields);
  my $fields_list = "user, " . join(", \n", values(%fields));

  my $sql = "SELECT u.id, DECODE(u.password, 'test12345678901234567890') AS password,
  pi.fio as fio,
  if(company.id IS NULL,b.deposit,cb.deposit) AS deposit,
  if(u.company_id=0, u.credit, if (u.credit=0, company.credit, u.credit)) AS credit,
  u.disable as disable,
  u.company_id as company_id,
  u.activate,
  u.expire,
  pi.phone,
  pi.email,
  pi.country_id,
  pi.address_street,
  pi.address_build,
  pi.address_flat,
  pi.comments,
  pi.contract_id,
  pi.contract_date,
  pi.contract_sufix,
  pi.pasport_num,
  pi.pasport_date,
  pi.pasport_grant,
  pi.zip,
  pi.city,
  dv.tp_id,
  INET_NTOA(dv.ip) AS ip,
  dv.CID,
  u.reduction,
  u.gid,
  u.registration,
  pi.comments,
  u.id
   FROM users u
   LEFT JOIN users_pi pi ON (u.uid = pi.uid)
   LEFT JOIN bills b ON (u.bill_id = b.id)
   LEFT JOIN companies company ON (u.company_id=company.id)
   LEFT JOIN bills cb ON (company.bill_id=cb.id)
   LEFT JOIN dv_main dv ON (u.uid=dv.uid)
   GROUP BY u.id";
  print "$sql\n" if ($DEBUG > 0);

  # return 0;

  my $q = $db->prepare($sql);
  $q->execute();
  my $query_fields = $q->{NAME};
  my $output       = '';
  my %logins_hash  = ();

  while (my @row = $q->fetchrow_array()) {
    my $LOGIN = $row[0];
    $logins_hash{$LOGIN}{LOGIN} = $row[0];
    for (my $i = 1 ; $i < $#row ; $i++) {
      if ($DEBUG > 3) {
        print "$i, $query_fields->[$i], $fields_rev{$query_fields->[$i]} -> $row[$i] \n";
      }
      $logins_hash{$LOGIN}{ $fields_rev{ $query_fields->[$i] } } = $row[$i];
    }

    #Extended params
    while (my ($k, $v) = each %EXTENDED_STATIC_FIELDS) {
      $logins_hash{$LOGIN}{$k} = $v;
    }

  }

  undef($q);
  return \%logins_hash;

}

#**************************************************
#
#**************************************************
sub utm5cards {
  my ($attr) = @_;

=comments
<?xml version="1.0" encoding="Windows-1251"?>
<UTM>
 <pool id='5' type='std'>
  <card id='11445' secret='817858938105' balance='25.0' currency='980' expire_date='31.12.2010' usage_date='01.09.2009' tp_id='0' />
  <card id='10810' secret='800909730456' balance='25.0' currency='980' expire_date='31.12.2010' usage_date='01.09.2009' tp_id='0' />
  <card id='20298' secret='167635967761' balance='25.0' currency='980' expire_date='31.12.2010' usage_date='��� ���' tp_id='0' />
  <card id='20297' secret='531258306760' balance='25.0' currency='980' expire_date='31.12.2010' usage_date='��� ���' tp_id='0' />
 </pool>
</UTM>
=cut

  if ($IMPORT_FILE eq '') {
    print "Select UTM5 Cards file\n";
    exit;
  }

  my $arr = file_content($IMPORT_FILE);

  require "/usr/abills/libexec/config.pl";

  shift(@$arr);
  my @sql_arr = ();
  foreach my $line (@$arr) {

    #print "$line\n";
    my @csv = split(/,/, $line);

    my $cards_id    = $csv[0];
    my $secret      = $csv[2];
    my $balance     = $csv[3];
    my $expire_date = '';
    my $status      = 0;
    if ($csv[5] =~ '(\d{2})\.(\d{2})\.(\d{4})') {
      $expire_date = "$3-$2-$1";
    }
    else {
      $expire_date = '0000-00-00';
    }

    if (length($csv[7]) > 6) {
      $status = 1;
    }

    #if ($line =~ /<card id='(\d+)'\s+secret='(\S+)' balance='([0-9\.\,]+)' currency='(\d+)' expire_date='(\d{2})\.(\d{2})\.(\d{4})' usage_date='��� ���' tp_id='0'/) {
    #my $cards_id = $1;
    #my $secret   = $2;
    #my $balance  = $3;
    #my $expire_date = "$7-$6-$5";
    push @sql_arr, "INSERT into cards_users (`serial`,`number`,`aid`, `expire`,`sum`, `pin`, `created`, `status`) values ('', '$cards_id', '1', '$expire_date', '$balance', ENCODE('$secret', '$conf{secretkey}'), now(), $status); ";

    #}
  }

  foreach my $line (@sql_arr) {
    print $line. "\n" if ($DEBUG > 1);
    if ($DEBUG < 5) {
      $db->do("$line");
    }
  }
}

#**************************************************
# Import from_TAB delimiter file
#**************************************************
sub get_file {
  my @FILE_FIELDS = ('3.CONTRACT_ID', '3.FIO', 'LOGIN', 'PASSWORD', '3.ADDRESS_STREET', '4.IP', '3.COMMENTS', '5.SUM', '4.TP_ID', '3.PHONE',);

  @FILE_FIELDS = split(/,/, $FILE_FIELDS);

  #$FILE_FIELDS[0] = 'LOGIN';
  #$FILE_FIELDS[1] = 'PASSWORD';

  my %logins_hash = ();
  my %TARIFS_HASH = ();
  my $TP_ID       = 0;

  my $rows = file_content($IMPORT_FILE);

  foreach my $line (@$rows) {
    my @cels      = split(/\t/, $line);
    my %tmp_hash  = ();
    my $COMMENTS  = '';
    my $cel_phone = '';

    print $line if ($DEBUG > 4);

    for (my $i = 0 ; $i <= $#cels ; $i++) {
      next if (!$FILE_FIELDS[$i]);

      $tmp_hash{ $FILE_FIELDS[$i] } = $cels[$i];
      print "$i/$FILE_FIELDS[$i] - $cels[$i]\n" if ($DEBUG > 0);

      if ($tmp_hash{ $FILE_FIELDS[$i] } =~ /^(\d{2})[-.](\d{2})[-.](\d{4})$/) {
        $tmp_hash{ $FILE_FIELDS[$i] } = "$3-$2-$1";
      }

      if ($FILE_FIELDS[$i] eq '3.ADDRESS_STREET') {

        #     if($cels[$i] =~ /(.+), �. (.+)|(.+), �. (.+), k�. (.+)/) {
        #        $tmp_hash{'3.ADDRESS_STREET'}=$1;
        #        $tmp_hash{'3.ADDRESS_BUILD'}=$2;
        #        $tmp_hash{'3.ADDRESS_FLAT'}=$3;
        #        print "Street: $tmp_hash{'3.ADDRESS_STREET'} / $tmp_hash{'3.ADDRESS_BUILD'} /$tmp_hash{'3.ADDRESS_FLAT'} \n" if ($debug > 0);
        #        #exit;
        #      }
      }
      elsif ($FILE_FIELDS[$i] eq '5.SUM') {
        $tmp_hash{ $FILE_FIELDS[$i] } =~ s/,/./g;
        if ($EXCHANGE_RATE > 0) {
          $tmp_hash{ $FILE_FIELDS[$i] } = $tmp_hash{ $FILE_FIELDS[$i] } * $EXCHANGE_RATE;
        }
      }
      elsif ($FILE_FIELDS[$i] eq '4.TP') {
        if (!$TARIFS_HASH{ $tmp_hash{ $FILE_FIELDS[$i] } }) {
          $TP_ID += 10;
          $TARIFS_HASH{ $tmp_hash{ $FILE_FIELDS[$i] } } = $TP_ID;
        }

        $tmp_hash{'4.TP_ID'} = $TARIFS_HASH{ $tmp_hash{ $FILE_FIELDS[$i] } };
      }
      elsif ($FILE_FIELDS[$i] eq '3.CONTRACT_ID') {
        $tmp_hash{ $FILE_FIELDS[$i] } =~ s/\-//g;
      }
      elsif ($FILE_FIELDS[$i] eq '3.PHONE') {
        $COMMENTS .= "PHONE: " . $tmp_hash{ $FILE_FIELDS[$i] };

        if ($tmp_hash{ $FILE_FIELDS[$i] } =~ s/_(.+)$//) {
          $cel_phone .= $1;
        }
        $tmp_hash{ $FILE_FIELDS[$i] } =~ s/,//g if ($tmp_hash{ $FILE_FIELDS[$i] });

        # print "$tmp_hash{$FILE_FIELDS[$i]} / $tmp_hash{'3._cel_phone'}\n";
      }
    }

    next if (!$tmp_hash{'LOGIN'});
    $tmp_hash{'3._cel_phone'} = $cel_phone if ($cel_phone);

    #$tmp_hash{'3.COMMENTS'}.=$COMMENTS;
    if ($tmp_hash{'F1'}) {
      $tmp_hash{'3.FIO'} .= "$tmp_hash{'F1'} $tmp_hash{'F2'} $tmp_hash{'F3'}";
    }

    $logins_hash{ $tmp_hash{'LOGIN'} } = \%tmp_hash;
    print "=====================\n" if ($DEBUG > 0);
  }

  if ($DEBUG > 1) {
    while (my ($k, $v) = each %TARIFS_HASH) {
      print "$k  -> $v\n";
    }

    exit if ($DEBUG > 5);
  }

  return \%logins_hash;
}

#**********************************************************
#
#**********************************************************
sub get_utm4_users {
  my %fields = (
    'LOGIN'    => 'login',
    'PASSWORD' => 'password',

    #  '1.ACTIVATE'     => 'activated',
    #  '1.EXPIRE' 	     => 'expired',
    #  '1.COMPANY_ID'   => '',
    '1.CREDIT' => 'credit',

    #  '1.GID' 	       => '',
    #  '1.REDUCTION'    => '',
    '1.REGISTRATION' => 'DATE_FORMAT(FROM_UNIXTIME(reg_date), \'%Y-%m-%d\')',
    '1.DISABLE'      => 'block',

    #  '3.ADDRESS_FLAT'   => '',
    '3.ADDRESS_STREET' => 'actual_address',

    #  '3.ADDRESS_BUILD'  => '',
    #  '3.COMMENTS'       => '',
    #  '3.CONTRACT_ID' 	 => '',
    '3.EMAIL' => 'email',
    '3.FIO'   => 'full_name',

    #  '3.PHONE'          => 'phone',

    #  '4.CID'            => '',
    #  '4.FILTER_ID'      => '',
    '4.IP' => 'ip',

    #  '4.NETMASK'        => '\'255.255.255.255\'',
    #  '4.SIMULTANEONSLY' => 'simultaneous_use',
    #  '4.SPEED'          => 'speed',
    '4.TP_ID' => 'tariff',

    #  '4.CALLBACK'       => 'allow_callback',

    '5.SUM' => 'bill',

    #  '5.DESCRIBE' 	     => "'Migration'",
    #  '5.ER'             => undef,
    #  '5.EXT_ID'         => undef,

    #  '6.USERNAME'       => 'email',
    #  '6.DOMAINS_SEL'     => $email_domain_id || 0,
    #  '6.COMMENTS'        => '',
    #  '6.MAILS_LIMIT'	    => 0,
    #  '6.BOX_SIZE'	      => 0,
    #  '6.ANTIVIRUS'	      => 0,
    #  '6.ANTISPAM'	      => 0,
    #  '6.DISABLE'	        => 0,
    #  '6.EXPIRE'	        => undef,
    #  '6.PASSWORD'	      => 'email_pass',
  );

  my %fields_rev = reverse(%fields);

  #my $fields_list = "user, ". join(", \n", values(%fields));
  my $fields_list = "id, " . join(", \n", values(%fields));

  my $sql = "SELECT $fields_list FROM users";
  print "$sql\n" if ($DEBUG > 0);

  my $q = $db->prepare($sql);
  $q->execute();
  my $query_fields = $q->{NAME};

  my $output      = '';
  my %logins_hash = ();

  while (my @row = $q->fetchrow_array()) {
    my $LOGIN = $row[0];

    for (my $i = 1 ; $i < $#row ; $i++) {
      if ($DEBUG > 3) {
        print "$i, $query_fields->[$i], $fields_rev{$query_fields->[$i]} -> $row[$i] \n";
      }

      $logins_hash{$LOGIN}{ $fields_rev{ $query_fields->[$i] } } = $row[$i];
    }

    if ($logins_hash{$LOGIN}{'6.USERNAME'} && $logins_hash{$LOGIN}{'6.USERNAME'} =~ /(\S+)\@/) {
      $logins_hash{$LOGIN}{'6.USERNAME'} = $1;
    }

    #Extended params
    while (my ($k, $v) = each %EXTENDED_STATIC_FIELDS) {
      $logins_hash{$LOGIN}{$k} = $v;
    }

  }

  undef($q);
  return \%logins_hash;

}

#**********************************************************
# Export from UTM5
#**********************************************************
sub get_utm5_users {

  my %fields = (
    'LOGIN'      => 'login',
    'PASSWORD'   => 'password',
    '1.ACTIVATE' => 'if(dp.start_date, DATE_FORMAT(FROM_UNIXTIME(dp.start_date), \'%Y-%m-%d\'), \'0000-00-00\')',
    '1.EXPIRE'   => 'if(dp.end_date, DATE_FORMAT(FROM_UNIXTIME(dp.end_date), \'%Y-%m-%d\'), \'0000-00-00\')',

    #  '1.COMPANY_ID'    => '',
    '1.CREDIT' => 'credit',
    '1.GID'    => 'if(gl.group_id, gl.group_id, 0)',

    #  '1.REDUCTION'     => '',
    '1.REGISTRATION' => 'FROM_UNIXTIME(u.create_date)',
    '1.DISABLE'      => 'if(a.is_blocked, 1, 0)',

    '3.ADDRESS_FLAT'   => 'flat_number',
    '3.ADDRESS_STREET' => 'if(t12.street!=\'\', t12.street, \'\')',
    '3.ADDRESS_BUILD'  => 'if(t12.number!=\'\', t12.number, \'\')',
    '3.COMMENTS'       => 'comments',

    #  '3.CONTRACT_ID'       => '',
    '3.EMAIL'         => 'if(u.email!=\'\', u.email, \'\')',
    '3.FIO'           => 'full_name',
    '3.PASPORT_GRANT' => 'passport',
    '3.PHONE'         => 'home_telephone',
    '3.COUNTRY_ID'    => '804',
    '3.ZIP'           => 'if(t12.post_code!=\'\', t12.post_code, \'\')',
    '3.CITY '         => 'if(t12.city!=\'\', t12.city, \'\')',

    '3._entrance'       => 'if(t12.building!=\'\', t12.building, \'\')',
    '3._work_telephone' => 'if(u.work_telephone!=\'\', u.work_telephone, \'\')',
    '3._mobile'         => 'if(u.mobile_telephone!=\'\', u.mobile_telephone, \'\')',
    '3._icq_number'     => 'if(u.icq_number!=\'\', u.icq_number, \'\')',
    '3._web_page'       => 'if(u.web_page!=\'\', u.web_page, \'\')',
    '3._old_id'         => 'if(u.id, u.id, \'\')',
    '3._tariff_name'    => 'if(t9.name!=\'\', t9.name, \'\')',
    '3._group_name'     => 'if(t11.group_name!=\'\', t11.group_name, \'\')',

    '4.CID' => 'if(t1.mac!=\'\', t1.mac, \'\')',

    #  '4.FILTER_ID'      => '',
    '4.IP' => 'if(inet_ntoa(t1.ip&0xffffffff), inet_ntoa(t1.ip&0xffffffff), \'\')',

    #  '4.NETMASK'        => '\'255.255.255.255\'',
    #  '4.SIMULTANEONSLY' => 'simultaneous_use',
    #  '4.SPEED'          => 'speed',
    '4.TP_ID' => 'if(atl.tariff_id, atl.tariff_id, 0)',

    #  '4.CALLBACK'       => 'allow_callback',

    '5.SUM' => 'balance',

    #  '5.DESCRIBE'       => "'Migration'",
    #  '5.ER'             => undef,
    #  '5.EXT_ID'         => undef,

    #  '6.USERNAME'       => 'email',
    #  '6.DOMAINS_SEL'     => $email_domain_id || 0,
    #  '6.COMMENTS'        => '',
    #  '6.MAILS_LIMIT'          => 0,
    #  '6.BOX_SIZE'       => 0,
    #  '6.ANTIVIRUS'              => 0,
    #  '6.ANTISPAM'       => 0,
    #  '6.DISABLE'          => 0,
    #  '6.EXPIRE'           => undef,
    #  '6.PASSWORD'       => 'email_pass',
  );

  my %fields_rev = reverse(%fields);
  my $fields_list = "u.login, " . join(", \n", values(%fields));

  my $sql = "select $fields_list
  FROM (users u, users_accounts ua, accounts a)
  LEFT JOIN users_groups_link gl ON (u.id=gl.user_id)
  LEFT JOIN account_tariff_link atl ON (a.id=atl.account_id and atl.is_deleted=0)
  LEFT JOIN discount_periods dp ON (atl.discount_period_id=dp.id)
  LEFT JOIN user_contacts uc ON (u.id=uc.uid)
  LEFT JOIN service_links t3 ON (t3.user_id = u.id and t3.is_deleted <> '1')
  LEFT JOIN iptraffic_service_links t2 ON (t2.id = t3.id and t2.is_deleted <> '1')
  LEFT JOIN ip_groups t1 ON (t1.ip_group_id = t2.ip_group_id and t1.is_deleted <> '1')
  LEFT JOIN tariffs t9 ON (atl.tariff_id = t9.id and t9.is_deleted  <> '1')
  LEFT JOIN groups t11 ON (t11.id = gl.group_id)
  LEFT JOIN houses t12 ON (t12.id = u.house_id)

  WHERE u.id=ua.uid
  and ua.account_id=a.id
  and a.is_deleted=0
  GROUP BY u.login
  ORDER BY 1


";

  if ($DEBUG > 5) {
    print $sql;
    return 0;
  }
  elsif ($DEBUG > 0) {
    print "$sql\n";
  }
  my $q = $db->prepare($sql);
  $q->execute();
  my $query_fields = $q->{NAME};

  my $output      = '';
  my %logins_hash = ();

  while (my @row = $q->fetchrow_array()) {
    my $LOGIN = $row[0];

    for (my $i = 1 ; $i <= $#row ; $i++) {
      if ($DEBUG > 3) {
        print "$i, $query_fields->[$i], " . $fields_rev{"$query_fields->[$i]"} . " -> $row[$i] \n";
      }

      $logins_hash{$LOGIN}{ $fields_rev{ $query_fields->[$i] } } = $row[$i];
    }

    if ($logins_hash{$LOGIN}{'6.USERNAME'} && $logins_hash{$LOGIN}{'6.USERNAME'} =~ /(\S+)\@/) {
      $logins_hash{$LOGIN}{'6.USERNAME'} = $1;
    }
    elsif ($logins_hash{$LOGIN}{'3.COMMENTS'}) {
      $logins_hash{$LOGIN}{'3.COMMENTS'} =~ s/\n//g;
    }

    #Extended params
    while (my ($k, $v) = each %EXTENDED_STATIC_FIELDS) {
      $logins_hash{$LOGIN}{$k} = $v;
    }

  }

  undef($q);
  return \%logins_hash;
}

#**********************************************************
# Export from UTM5
#**********************************************************
sub get_utm5pg_users {

  my %fields = (
    'LOGIN'      => 'login',
    'PASSWORD'   => 'password',
    '1.ACTIVATE' => 'if(dp.start_date, DATE_FORMAT(FROM_UNIXTIME(dp.start_date), \'%Y-%m-%d\'), \'0000-00-00\')',
    '1.EXPIRE'   => 'if(dp.end_date, DATE_FORMAT(FROM_UNIXTIME(dp.end_date), \'%Y-%m-%d\'), \'0000-00-00\')',

    #  '1.COMPANY_ID'   => '',
    '1.CREDIT' => 'credit',
    '1.GID'    => 'gid',

    #  '1.REDUCTION'    => '',
    '1.REGISTRATION' => 'FROM_UNIXTIME(u.create_date)',
    '1.DISABLE'      => 'disable',

    '3.ADDRESS_FLAT'   => 'flat_number',
    '3.ADDRESS_STREET' => 'actual_address',
    '3.ADDRESS_BUILD'  => 'house_id',
    '3.COMMENTS'       => 'comments',

    #  '3.CONTRACT_ID'       => '',
    '3.EMAIL'         => 'if(u.email, u.email, \'\')',
    '3.FIO'           => 'full_name',
    '5.PASPORT_GRANT' => 'passport',
    '3.PHONE'         => 'home_telephone',

    #  '4.CID'            => '',
    #  '4.FILTER_ID'      => '',
    #  '4.IP'             => 'ip',
    #  '4.NETMASK'        => '\'255.255.255.255\'',
    #  '4.SIMULTANEONSLY' => 'simultaneous_use',
    #  '4.SPEED'          => 'speed',
    '4.TP_ID' => 'tp',    #'COALESCE(atl.tariff_id, 0)',

    #  '4.CALLBACK'       => 'allow_callback',

    '5.SUM' => 'balance',

    #  '5.DESCRIBE'       => "'Migration'",
    #  '5.ER'             => undef,
    #  '5.EXT_ID'         => undef,

    #  '6.USERNAME'       => 'email',
    #  '6.DOMAINS_SEL'     => $email_domain_id || 0,
    #  '6.COMMENTS'        => '',
    #  '6.MAILS_LIMIT'          => 0,
    #  '6.BOX_SIZE'       => 0,
    #  '6.ANTIVIRUS'              => 0,
    #  '6.ANTISPAM'       => 0,
    #  '6.DISABLE'          => 0,
    #  '6.EXPIRE'           => undef,
    #  '6.PASSWORD'       => 'email_pass',
  );

  my %fields_rev = reverse(%fields);

  #my $fields_list = "u.login, ". join(", \n", values(%fields));
  #print $fields_list;
  #my $sql = "select $fields_list
  # FROM users u, users_accounts ua, accounts a
  #  LEFT JOIN users_groups_link gl ON (u.id=gl.user_id)
  #  LEFT JOIN account_tariff_link atl ON (a.id=atl.account_id and atl.is_deleted=0)
  #  LEFT JOIN discount_periods dp ON (atl.discount_period_id=dp.id)
  #  LEFT JOIN user_contacts uc ON (u.id=uc.uid)
  #  WHERE u.id=ua.uid
  #  and ua.account_id=a.id
  #  ORDER BY 1
  #";

  my $sql = "select  u.login, full_name, COALESCE(to_char(TIMESTAMP WITH TIME ZONE 'epoch' + dp.end_date * interval '1 second', 'YYYY-MM-DD'), '0000-00-00'),
password, balance,  comments,
COALESCE(to_char(TIMESTAMP WITH TIME ZONE 'epoch' + dp.start_date * interval '1 second', 'YYYY-MM-DD'), '0000-00-00'),
house_id, TIMESTAMP WITH TIME ZONE 'epoch' + u.create_date * interval '1 second', login, COALESCE(u.is_blocked, 0) as disable, credit,
passport,  COALESCE(u.email, '') as email, flat_number,  actual_address,	COALESCE(gl.group_id, 0) as gid,
COALESCE(atl.tariff_id, 0) AS TP, full_name, home_telephone
FROM accounts a  INNER JOIN users_accounts ua ON a.id = ua.account_id
INNER JOIN users u ON ua.uid = u.id
LEFT JOIN users_groups_link gl ON (u.id=gl.user_id)
LEFT JOIN account_tariff_link atl ON (a.id=atl.account_id and atl.is_deleted=0)
LEFT JOIN discount_periods dp ON (atl.discount_period_id=dp.id)
LEFT JOIN user_contacts uc ON (u.id=uc.uid)
ORDER BY u.login";

  if ($DEBUG > 4) {
    print $sql;
    return 0;
  }
  elsif ($DEBUG > 0) {
    print "$sql\n";
  }

  my $q = $db->prepare($sql);
  $q->execute();
  my $query_fields = $q->{NAME};

  my $output      = '';
  my %logins_hash = ();

  while (my @row = $q->fetchrow_array()) {
    my $LOGIN = $row[0];

    for (my $i = 1 ; $i < $#row ; $i++) {
      if ($DEBUG > 3) {
        print "$i, $query_fields->[$i], " . $fields_rev{"$query_fields->[$i]"} . " -> $row[$i] \n";
      }

      $logins_hash{$LOGIN}{ $fields_rev{ $query_fields->[$i] } } = $row[$i];
    }

    if ($logins_hash{$LOGIN}{'6.USERNAME'} && $logins_hash{$LOGIN}{'6.USERNAME'} =~ /(\S+)\@/) {
      $logins_hash{$LOGIN}{'6.USERNAME'} = $1;
    }

    #Extended params
    while (my ($k, $v) = each %EXTENDED_STATIC_FIELDS) {
      $logins_hash{$LOGIN}{$k} = $v;
    }

  }

  undef($q);
  return \%logins_hash;
}

#**********************************************************
#
#**********************************************************
sub get_freenibs_users {
  my ($attr) = @_;

  my %fields = (
    'LOGIN'    => 'user',
    'PASSWORD' => 'password',

    #  '1.ACTIVATE'     => 'activated',
    '1.EXPIRE' => 'expired',

    #  '1.COMPANY_ID'   => '',
    '1.CREDIT' => 'credit',

    #  '1.GID' 	       => '',
    #  '1.REDUCTION'    => '',
    '1.REGISTRATION' => 'add_date',
    '1.DISABLE'      => 'blocked',

    #  '3.ADDRESS_FLAT'   => '',
    '3.ADDRESS_STREET' => 'address',

    #  '3.ADDRESS_BUILD'  => '',
    #  '3.COMMENTS'       => '',
    #  '3.CONTRACT_ID' 	 => '',
    #  '3.EMAIL'          => '',
    '3.FIO'   => 'fio',
    '3.PHONE' => 'phone',

    #  '4.CID'            => '',
    #  '4.FILTER_ID'      => '',
    '4.IP' => 'framed_ip',

    #  '4.NETMASK'        => '\'255.255.255.255\'',
    '4.SIMULTANEONSLY' => 'simultaneous_use',
    '4.TP_ID'          => 'gid',
    '4.CALLBACK'       => 'allow_callback',

    '5.SUM' => 'deposit',

    #  '5.DESCRIBE' 	     => "'Migration'",
    #  '5.ER'             => undef,
    #  '5.EXT_ID'         => undef,

  );

  if ($attr->{MABILL}) {
    $fields{'4.SPEED'}    = 'speed';
    $fields{'6.USERNAME'} = 'email', $fields{'6.DOMAINS_SEL'} = $EMAIL_DOMAIN_ID || 0;
    $fields{'PASSWORD'}   = 'if(crypt_method=1, email_pass, password)';

    #  '6.COMMENTS'        => '',
    #  '6.MAILS_LIMIT'	    => 0,
    #  '6.BOX_SIZE'	      => 0,
    #  '6.ANTIVIRUS'	      => 0,
    #  '6.ANTISPAM'	      => 0,
    #  '6.DISABLE'	        => 0,
    #  '6.EXPIRE'	        => undef,
    $fields{'6.PASSWORD'} = 'email_pass';
  }

  my %fields_rev = reverse(%fields);
  my $fields_list = "user, " . join(", \n", values(%fields));

  my $sql = "SELECT $fields_list FROM users";
  print "$sql\n" if ($DEBUG > 0);

  my $q = $db->prepare($sql);
  $q->execute();
  my $query_fields = $q->{NAME};

  my $output      = '';
  my %logins_hash = ();

  while (my @row = $q->fetchrow_array()) {
    my $LOGIN = $row[0];

    for (my $i = 1 ; $i < $#row ; $i++) {
      if ($DEBUG > 3) {
        print "$i, $query_fields->[$i], $fields_rev{$query_fields->[$i]} -> $row[$i] \n";
      }

      $logins_hash{$LOGIN}{ $fields_rev{ $query_fields->[$i] } } = $row[$i];
    }

    if ($logins_hash{$LOGIN}{'6.USERNAME'} && $logins_hash{$LOGIN}{'6.USERNAME'} =~ /(\S+)\@/) {
      $logins_hash{$LOGIN}{'6.USERNAME'} = $1;
    }

    #Extended params
    while (my ($k, $v) = each %EXTENDED_STATIC_FIELDS) {
      $logins_hash{$LOGIN}{$k} = $v;
    }

  }

  undef($q);
  return \%logins_hash;
}

#**********************************************************
#
#**********************************************************
sub show {
  my ($logins_info, $attr) = @_;

  my $counts = 0;
  my $output = '';

  print "Output format: $FORMAT\n" if ($DEBUG > 1);

  my %exaption = (
    'LOGIN'    => 1,
    'PASSWORD' => 2
  );

  my @titls = sort keys %$logins_info;
  my $login = $titls[0];

  @titls = sort keys %{ $logins_info->{$login} };

  if ($ARGUMENTS->{LOGIN2UID} && !$logins_info->{$login}{'1.UID'}) {
    push @titls, '1.UID';
  }

  if ($FORMAT eq 'html') {
    $output = "<table border=1>\n" . "<tr><th>LOGIN</th>
	<th>PASSWORD</th>\n";

    foreach my $column_title (@titls) {
      next if ($exaption{$column_title});
      $output .= "<th>$column_title</th>\n";
    }
    $output .= "</tr>\n";
  }

  foreach $login (sort keys %$logins_info) {

    #add login to uid
    if ($ARGUMENTS->{LOGIN2UID} && !$logins_info->{$login}{'1.UID'}) {
      $logins_info->{$login}{'1.UID'} = $login;
    }

    next if (!$login);
    print "$login\n" if ($DEBUG > 0);

    if ($FORMAT eq 'html') {
      $output .= "<tr><td>$logins_info->{$login}{'LOGIN'}</td><td>$logins_info->{$login}{'PASSWORD'}</td>";
      foreach my $column_title (@titls) {
        if (!$column_title) {
          print "//" . $column_title;
          exit;
        }
        next if ($exaption{$column_title});
        $output .= "<td>" . (($logins_info->{$login}{$column_title}) ? $logins_info->{$login}{$column_title} : '') . "</td>";
      }
      $output .= "</tr>\n";
    }
    else {
      $output .= "$logins_info->{$login}{'LOGIN'}\t" . (($logins_info->{$login}{'PASSWORD'}) ? $logins_info->{$login}{'PASSWORD'} : '') . "\t";

      foreach my $column_title (@titls) {
        next if ($exaption{$column_title});

        if ($column_title eq '4.TP_ID' && $TP_MIGRATION{ $logins_info->{$login}{$column_title} }) {
          $logins_info->{$login}{$column_title} = $TP_MIGRATION{ $logins_info->{$login}{$column_title} };
        }

        #Address full
        if ($column_title eq '3.ADDRESS_FULL') {
          if ($ARGUMENTS->{ADDRESS_DELIMITER}) {
            my ($delimiter1, $delimiter2) = split(/,/, $ARGUMENTS->{ADDRESS_DELIMITER}, 2);

            if (!$delimiter2) {
              $delimiter2 = '';
            }

            $logins_info->{$login}{$column_title} =~ m/(.+)$delimiter1(.+)$delimiter2(.{0,10})/;

            my ($ADDRESS_STREET, $ADDRESS_BUILD, $ADDRESS_FLAT) = ($1, $2, $3);

            if ($ADDRESS_STREET) {
              $output .= qq{3.ADDRESS_STREET="$ADDRESS_STREET"\t};
            }
            else {
              $output .= qq{3.ADDRESS_STREET="$logins_info->{$login}{$column_title}"\t};
            }

            if ($ADDRESS_BUILD) {
              $output .= qq{3.ADDRESS_BUILD="$ADDRESS_BUILD"\t};
            }

            if ($ADDRESS_FLAT) {
              $output .= qq{3.ADDRESS_FLAT="$3"\t};
            }

            next;
          }
        }

        #print "$login $column_title\n" if(! $logins_info->{$login}{$column_title});
        if ($logins_info->{$login}{$column_title}) {
          $output .= "$column_title=\"" . $logins_info->{$login}{$column_title} . "\"\t";
        }
      }

      if ($ARGUMENTS->{SKIP_ERROR_PARAM}) {
        $output .= "SKIP_ERRORS=1\t4.DV_SKIP_FEE=1\t";
      }

      if ($ARGUMENTS->{ADD_PARAMS}) {
        $ARGUMENTS->{ADD_PARAMS} =~ s/,/\t/g;
        $output .= "$ARGUMENTS->{ADD_PARAMS}\t";
      }

      $output .= "\n";
    }

    $counts++;
  }

  if ($FORMAT eq 'html') {
    $output .= "</table>\n";
  }

  print "$output\n";
  print "ROWS: $counts\n";
}

#*******************************************************************
# Parse comand line arguments
# get_unisys(@$argv)
#*******************************************************************
sub get_unisys {

  my %fields = (
    'LOGIN'      => 'name',
    'PASSWORD'   => '\'-\'',
    '1.ACTIVATE' => 'DATE_FORMAT(allowsince, \'Y-%m-%d\')',
    '1.EXPIRE'   => 'DATE_FORMAT(allowsince, \'Y-%m-%d\')',

    #  '1.COMPANY_ID'   => '',
    #  '1.CREDIT'         => '',
    #  '1.GID'              => 'if(gl.group_id, gl.group_id, 0)',
    #  '1.REDUCTION'    => '',
    '1.REGISTRATION' => 'since',

    #  '1.DISABLE'      => 'if(u.is_blocked, u.is_blocked, 0)',

    #  '3.ADDRESS_FLAT'   => 'address',
    '3.ADDRESS_STREET' => 'address',

    #  '3.ADDRESS_BUILD'  => 'house_id',
    '3.COMMENTS' => 'rem',

    #  '3.CONTRACT_ID'       => '',
    '3.EMAIL' => 'email',
    '3.FIO'   => 'fullname',

    #  '5.PASPORT_GRANT'  => 'passport',
    '3.PHONE' => 'phone',

    #  '4.CID'            => '',
    #  '4.FILTER_ID'      => '',
    #  '4.IP'             => 'ip',
    #  '4.NETMASK'        => '\'255.255.255.255\'',
    #  '4.SIMULTANEONSLY' => 'simultaneous_use',
    #  '4.SPEED'          => 'speed',
    #  '4.TP_ID'          => 'if(atl.tariff_id, atl.tariff_id, 0)',
    #  '4.CALLBACK'       => 'allow_callback',

    '5.SUM' => 'balance',

    #  '5.DESCRIBE'       => "'Migration'",
    #  '5.ER'             => undef,
    #  '5.EXT_ID'         => undef,

    #  '6.USERNAME'       => 'email',
    #  '6.DOMAINS_SEL'     => $email_domain_id || 0,
    #  '6.COMMENTS'        => '',
    #  '6.MAILS_LIMIT'          => 0,
    #  '6.BOX_SIZE'       => 0,
    #  '6.ANTIVIRUS'              => 0,
    #  '6.ANTISPAM'       => 0,
    #  '6.DISABLE'          => 0,
    #  '6.EXPIRE'           => undef,
    #  '6.PASSWORD'       => 'email_pass',
  );

  my %fields_rev = reverse(%fields);
  my $fields_list = "name, " . join(", \n", values(%fields));

  my $sql = "select $fields_list
  FROM users
  ORDER BY 1
";

  if ($DEBUG > 4) {
    print $sql;
    return 0;
  }
  elsif ($DEBUG > 0) {
    print "$sql\n";
  }
  my $q = $db->prepare($sql);
  $q->execute();
  my $query_fields = $q->{NAME};

  my $output      = '';
  my %logins_hash = ();

  while (my @row = $q->fetchrow_array()) {
    my $LOGIN = $row[0];

    for (my $i = 1 ; $i < $#row ; $i++) {
      if ($DEBUG > 3) {
        print "$i, $query_fields->[$i], " . $fields_rev{"$query_fields->[$i]"} . " -> $row[$i] \n";
      }

      $logins_hash{$LOGIN}{ $fields_rev{ $query_fields->[$i] } } = $row[$i];
    }

    if ($logins_hash{$LOGIN}{'6.USERNAME'} && $logins_hash{$LOGIN}{'6.USERNAME'} =~ /(\S+)\@/) {
      $logins_hash{$LOGIN}{'6.USERNAME'} = $1;
    }

    #Extended params
    while (my ($k, $v) = each %EXTENDED_STATIC_FIELDS) {
      $logins_hash{$LOGIN}{$k} = $v;
    }

  }

  undef($q);
  return \%logins_hash;

}

#*******************************************************************
# Parse comand line arguments
# help(@$argv)
#*******************************************************************
sub help {

  print << "[END]";
ABillS Migration system Version: $VERSION
(http://abills.net.ua)

  Options:
    DEFAULT_PASSWORD    - default  password for empty passwords
    PASSSWD_ENCRYPTION_KEY - Password encryption key
    EMAIL_CREATE        - create email accounts
    EMAIL_DOMAIN        - ABillS E-mail domain ( CHECK '/ System configuration/ E-MAIL/ Domains/' )
    DEBUG               - Enable debug
    ADDRESS_DELIMITER=  - Addreess delimeter for field 3.ADDRESS_FULL (Address delimiter street_name[delimeter1]build[delimiter2][flat])
                          ADDRESS_DELIMITER="[delimiter1],[delimiter2]"
    SKIP_ERROR_PARAM=1  - Skip error and fees (Add:  SKIP_ERRORS=1	4.DV_SKIP_FEE=1)
    ADD_PARAMS=         - Add ext params with coma delimeter (ADD_PARAMS="1.GID=1000,5.STATUS=5")
    NO_DEPOSIT          - Don\'t transfer deposit
    FROM                - Migration From:
                            freenibs
                            mabill
                            utm4
                            utm5
                            utm5pg
                            file      - Tab delimiter file
                            utm5cards - require IMPORT_FILE paraments with utm cards
                            abills    - get users from another abills
                            mikbill - get users from mikbill
                              mikbill_deleted - get deleted users from mikbill
                              mikbill_blocked - get blocked users from mikbill
                            nodeny
                           	traffpro
                            stargazer    - MySQL DB
                            stargazer_pg - stargazer Postgree DB
                            lms
                            lms_nodes (IP, MAC adresses for lms users)
                            odbc
    SYNC_DEPOSIT        -  filename to sync deposit ( ./2abills.pl FROM=file SYNC_DEPOSIT=/usr/deposits )
    IMPORT_FILE=[file]  - Tab delimiter file
    FILE_FIELDS=[list,.]- Tab delimiter fields position (FILE_FIELDS=LOGIN,PASSWORD,3.FIO...)
    TP_MIGRATION=[file] - File with TP migration information.
                          Format:
                           old_tp=abills_tp_id
    LOGIN2UID           - Convert login to uid for digit logins
    ADD_NAS             - Add nas servers from file. Fields defined via FILE_FIELDS=... option
    DB_HOST             -
    DB_USER             -
    DB_PASSWORD         -
    DB_CHARSET          -
    DB_NAME             -
    HTML                - Show export file in HTML FORMAT
    help                - This help
[END]

}

#*******************************************************************
# Parse comand line arguments
# parse_arguments(@$argv)
#*******************************************************************
sub parse_arguments {
  my ($argv) = @_;

  my %args = ();

  foreach my $line (@$argv) {
    if ($line =~ /=/) {
      my ($k, $v) = split(/=/, $line, 2);
      $args{"$k"} = (defined($v)) ? $v : '';
    }
    else {
      $args{"$line"} = 1;
    }
  }
  return \%args;
}

#  `tos` tinyint(1) default NULL,
#  `do_with_tos` tinyint(1) default NULL,
#  `direction` tinyint(1) default NULL,
#  `fixed` tinyint(1) default NULL,
#  `fixed_cost` double(16,6) default NULL,
#  `activation_time` bigint(15) default NULL,
#  `total_time_limit` bigint(15) default NULL,
#  `month_time_limit` bigint(15) default NULL,
#  `week_time_limit` bigint(15) default NULL,
#  `day_time_limit` bigint(15) default NULL,
#  `total_traffic_limit` bigint(15) default NULL,
#  `month_traffic_limit` bigint(15) default NULL,
#  `week_traffic_limit` bigint(15) default NULL,
#  `day_traffic_limit` bigint(15) default NULL,
#  `total_money_limit` double(16,6) default NULL,
#  `month_money_limit` double(16,6) default NULL,
#  `week_money_limit` double(16,6) default NULL,
#  `day_money_limit` double(16,6) default NULL,
#  `login_time` varchar(254) default NULL,
#  `huntgroup_name` varchar(64) default NULL,
#
#  `port_limit` smallint(5) default NULL,
#  `session_timeout` bigint(15) default NULL,
#  `idle_timeout` bigint(15) default NULL,
#  `allowed_prefixes` varchar(64) default NULL,
#  `no_pass` tinyint(1) default NULL,
#  `no_acct` tinyint(1) default NULL,
#
#  `other_params` varchar(254) default NULL,
#  `total_time` bigint(15) NOT NULL default '0',
#  `total_traffic` bigint(15) NOT NULL default '0',
#  `total_money` double(16,6) NOT NULL default '0.000000',
#  `last_connection` date NOT NULL default '0000-00-00',
#  `framed_ip` varchar(16) NOT NULL default '',
#  `framed_mask` varchar(16) NOT NULL default '',
#  `callback_number` varchar(64) NOT NULL default '',
#  `speed` varchar(10) NOT NULL default '0',
#  PRIMARY KEY  (`uid`),
#  KEY `user` (`user`)

#**********************************************************
# Export from Mikbill
#**********************************************************
sub get_mikbill {

  my %fields = (
    'LOGIN'            => 'user',
    'PASSWORD'         => 'password',
    '1.EXPIRE'         => 'expired',
    '1.CREDIT'         => 'credit',
    '1.REGISTRATION'   => 'add_date',
    '1.DISABLE'        => 'blocked',
    '3.ADDRESS_FLAT'   => 'app',
    '3.ADDRESS_STREET' => 'address',
    '3.ADDRESS_BUILD'  => 'houseid',
    '3.COMMENTS'       => 'prim',
    '3.CONTRACT_ID'    => 'numdogovor',
    '3.EMAIL'          => 'email',
    '3.FIO'            => 'fio',
    '5.PASPORT_GRANT'  => 'passportserie',
    '3.PHONE'          => 'phone',
    '3._mob_tel'       => 'mob_tel',
    '4.IP'             => 'framed_ip',
    '4.NETMASK'        => 'framed_mask',
    '4.TP_ID'          => 'gid',
    '5.SUM'            => 'deposit',
  );

  my %fields_rev = reverse(%fields);
  my $fields_list = "user, " . join(", \n", values(%fields));

  my $sql = "SELECT
user,
user,
password,
expired,
credit,
add_date,
blocked,
app,
address,
h.house as houseid,
prim,
numdogovor,
email,
fio,
passportserie,
phone,
mob_tel,
framed_ip,
framed_mask,
gid,
deposit
  FROM users
  LEFT JOIN lanes_houses h ON ( users.houseid = h.houseid )";

  #print $sql;
  if ($DEBUG > 4) {
    print $sql;
    return 0;
  }
  elsif ($DEBUG > 0) {
    print "$sql\n";
  }
  my $q = $db->prepare($sql);
  $q->execute();
  my $query_fields = $q->{NAME};

  my $output      = '';
  my %logins_hash = ();

  while (my @row = $q->fetchrow_array()) {
    my $LOGIN = $row[0];

    for (my $i = 1 ; $i <= $#row ; $i++) {
      if ($DEBUG > 3) {
        print "$i, $query_fields->[$i], " . $fields_rev{"$query_fields->[$i]"} . " -> $row[$i] \n";
      }

      $logins_hash{$LOGIN}{ $fields_rev{ $query_fields->[$i] } } = $row[$i];
    }

    if ($logins_hash{$LOGIN}{'6.USERNAME'} && $logins_hash{$LOGIN}{'6.USERNAME'} =~ /(\S+)\@/) {
      $logins_hash{$LOGIN}{'6.USERNAME'} = $1;
    }
    elsif ($logins_hash{$LOGIN}{'3.COMMENTS'}) {
      $logins_hash{$LOGIN}{'3.COMMENTS'} =~ s/\n//g;
    }

    #Extended params
    while (my ($k, $v) = each %EXTENDED_STATIC_FIELDS) {
      $logins_hash{$LOGIN}{$k} = $v;
    }

  }

  undef($q);
  return \%logins_hash;
}

#**********************************************************
#
#**********************************************************
sub get_mikbill_deleted {

  my %fields = (
    'LOGIN'            => 'user',
    'PASSWORD'         => 'password',
    '1.EXPIRE'         => 'expired',
    '1.CREDIT'         => 'credit',
    '1.REGISTRATION'   => 'add_date',
    '1.DISABLE'        => 'blocked',
    '3.ADDRESS_FLAT'   => 'app',
    '3.ADDRESS_STREET' => 'address',
    '3.ADDRESS_BUILD'  => 'houseid',
    '3.COMMENTS'       => 'prim',
    '3.CONTRACT_ID'    => 'numdogovor',
    '3.EMAIL'          => 'email',
    '3.FIO'            => 'fio',
    '5.PASPORT_GRANT'  => 'passportserie',
    '3.PHONE'          => 'phone',
    '3._mob_tel'       => 'mob_tel',
    '4.IP'             => 'framed_ip',
    '4.NETMASK'        => 'framed_mask',
    '4.TP_ID'          => 'gid',
    '5.SUM'            => 'deposit',
  );

  my %fields_rev = reverse(%fields);
  my $fields_list = "user, " . join(", \n", values(%fields));

  my $sql = "SELECT
user,
user,
password,
expired,
credit,
add_date,
'1' as blocked,
app,
address,
h.house as houseid,
prim,
numdogovor,
email,
fio,
passportserie,
phone,
mob_tel,
framed_ip,
framed_mask,
gid,
deposit
  FROM usersdel
  LEFT JOIN lanes_houses h ON ( usersdel.houseid = h.houseid )";

  #print $sql;
  if ($DEBUG > 4) {
    print $sql;
    return 0;
  }
  elsif ($DEBUG > 0) {
    print "$sql\n";
  }
  my $q = $db->prepare($sql);
  $q->execute();
  my $query_fields = $q->{NAME};

  my $output      = '';
  my %logins_hash = ();

  while (my @row = $q->fetchrow_array()) {
    my $LOGIN = $row[0];

    for (my $i = 1 ; $i <= $#row ; $i++) {
      if ($DEBUG > 3) {
        print "$i, $query_fields->[$i], " . $fields_rev{"$query_fields->[$i]"} . " -> $row[$i] \n";
      }

      $logins_hash{$LOGIN}{ $fields_rev{ $query_fields->[$i] } } = $row[$i];
    }

    if ($logins_hash{$LOGIN}{'6.USERNAME'} && $logins_hash{$LOGIN}{'6.USERNAME'} =~ /(\S+)\@/) {
      $logins_hash{$LOGIN}{'6.USERNAME'} = $1;
    }
    elsif ($logins_hash{$LOGIN}{'3.COMMENTS'}) {
      $logins_hash{$LOGIN}{'3.COMMENTS'} =~ s/\n//g;
    }

    #Extended params
    while (my ($k, $v) = each %EXTENDED_STATIC_FIELDS) {
      $logins_hash{$LOGIN}{$k} = $v;
    }

  }

  undef($q);
  return \%logins_hash;
}

#**********************************************************
# GET bloked users from db mikbill
#**********************************************************
sub get_mikbill_blocked {

  my %fields = (
    'LOGIN'            => 'user',
    'PASSWORD'         => 'password',
    '1.EXPIRE'         => 'expired',
    '1.CREDIT'         => 'credit',
    '1.REGISTRATION'   => 'add_date',
    '4.STATUS'         => 'blocked',
    '3.ADDRESS_FLAT'   => 'app',
    '3.ADDRESS_STREET' => 'address',
    '3.ADDRESS_BUILD'  => 'houseid',
    '3.COMMENTS'       => 'prim',
    '3.CONTRACT_ID'    => 'numdogovor',
    '3.EMAIL'          => 'email',
    '3.FIO'            => 'fio',
    '5.PASPORT_GRANT'  => 'passportserie',
    '3.PHONE'          => 'phone',
    '3._mob_tel'       => 'mob_tel',
    '4.IP'             => 'framed_ip',
    '4.NETMASK'        => 'framed_mask',
    '4.TP_ID'          => 'gid',
    '5.SUM'            => 'deposit',
  );

  my %fields_rev = reverse(%fields);
  my $fields_list = "user, " . join(", \n", values(%fields));

  my $sql = "SELECT
user,
user,
password,
expired,
credit,
add_date,
'1' as blocked,
app,
address,
h.house as houseid,
prim,
numdogovor,
email,
fio,
passportserie,
phone,
mob_tel,
framed_ip,
framed_mask,
gid,
deposit
  FROM usersblok
  LEFT JOIN lanes_houses h ON ( usersblok.houseid = h.houseid )";

  #print $sql;
  if ($DEBUG > 4) {
    print $sql;
    return 0;
  }
  elsif ($DEBUG > 0) {
    print "$sql\n";
  }
  my $q = $db->prepare($sql);
  $q->execute();
  my $query_fields = $q->{NAME};

  my $output      = '';
  my %logins_hash = ();

  while (my @row = $q->fetchrow_array()) {
    my $LOGIN = $row[0];

    for (my $i = 1 ; $i <= $#row ; $i++) {
      if ($DEBUG > 3) {
        print "$i, $query_fields->[$i], " . $fields_rev{"$query_fields->[$i]"} . " -> $row[$i] \n";
      }

      $logins_hash{$LOGIN}{ $fields_rev{ $query_fields->[$i] } } = $row[$i];
    }

    if ($logins_hash{$LOGIN}{'6.USERNAME'} && $logins_hash{$LOGIN}{'6.USERNAME'} =~ /(\S+)\@/) {
      $logins_hash{$LOGIN}{'6.USERNAME'} = $1;
    }
    elsif ($logins_hash{$LOGIN}{'3.COMMENTS'}) {
      $logins_hash{$LOGIN}{'3.COMMENTS'} =~ s/\n//g;
    }

    #Extended params
    while (my ($k, $v) = each %EXTENDED_STATIC_FIELDS) {
      $logins_hash{$LOGIN}{$k} = $v;
    }

  }

  undef($q);
  return \%logins_hash;
}

#**********************************************************
# Export from Nodeny
# 49.xx
# 50.32
#**********************************************************
sub get_nodeny {

  $encryption_key = "hardpass3" if (!$encryption_key);

  my %fields = (
    '1.UID',     => 'id',
    'LOGIN'      => 'name',
    'PASSWORD'   => "AES_DECRYPT(passwd, \'$encryption_key\')",
    '1.ACTIVATE' => 'DATE_FORMAT(FROM_UNIXTIME(contract_date), \'%Y-%m-%d\')',

    #  '1.EXPIRE'			=> 'expired',
    #  '1.COMPANY_ID'		=> '',
    #  '1.CREDIT'			=> 'credit',
    '1.GID'       => 'grp',
    '1.REDUCTION' => 'discount',

    #  '1.REGISTRATION'		=> 'add_date',
    #  '1.DISABLE'			=> 'blocked',

    #  '3.ADDRESS_FLAT'		=> 'app',
    #  '3.ADDRESS_STREET'	=> 'address',
    #  '3.ADDRESS_BUILD'		=> 'houseid',
    '3.COMMENTS'    => 'comment',
    '3.CONTRACT_ID' => 'contract',

    #  '3.EMAIL'				=> 'email',
    '3.FIO' => 'fio',

    #  '5.PASPORT_GRANT'		=> 'passportserie',
    #  '3.PHONE'				=> 'mob_tel',

    #  '4.CID'				=> '',
    #  '4.FILTER_ID'		=> '',
    '4.IP' => 'ip',

    #  '4.NETMASK'			=> 'framed_mask',
    #  '4.SIMULTANEONSLY'	=> 'simultaneous_use',
    #  '4.SPEED'			=> 'speed',
    '4.TP_ID' => 'paket',

    #  '4.CALLBACK'			=> 'allow_callback',

    '5.SUM' => 'balance',

    #  '5.DESCRIBE'			=> "'Migration'",
    #  '5.ER'				=> undef,
    #  '5.EXT_ID'			=> undef,

    #  '6.USERNAME'			=> 'email',
    #  '6.DOMAINS_SEL'		=> $email_domain_id || 0,
    #  '6.COMMENTS'			=> '',
    #  '6.MAILS_LIMIT'		=> 0,
    #  '6.BOX_SIZE'			=> 0,
    #  '6.ANTIVIRUS'		=> 0,
    #  '6.ANTISPAM'			=> 0,
    #  '6.DISABLE'          => 0,
    #  '6.EXPIRE'			=> undef,
    #  '6.PASSWORD'			=> 'email_pass',
  );

  my %fields_rev = reverse(%fields);
  my $fields_list = "name, " . join(", \n", values(%fields));

  my $sql = "SELECT $fields_list FROM users";

  #print $sql;
  if ($DEBUG > 4) {
    print $sql;
    return 0;
  }
  elsif ($DEBUG > 0) {
    print "$sql\n";
  }
  my $q = $db->prepare($sql);
  $q->execute();
  my $query_fields = $q->{NAME};

  my $output      = '';
  my %logins_hash = ();

  while (my @row = $q->fetchrow_array()) {
    my $LOGIN = $row[0];

    for (my $i = 1 ; $i < $#row ; $i++) {
      if ($DEBUG > 3) {
        print "$i, $query_fields->[$i], " . $fields_rev{"$query_fields->[$i]"} . " -> $row[$i] \n";
      }

      $logins_hash{$LOGIN}{ $fields_rev{ $query_fields->[$i] } } = $row[$i];
    }

    if ($logins_hash{$LOGIN}{'6.USERNAME'} && $logins_hash{$LOGIN}{'6.USERNAME'} =~ /(\S+)\@/) {
      $logins_hash{$LOGIN}{'6.USERNAME'} = $1;
    }
    elsif ($logins_hash{$LOGIN}{'3.COMMENTS'}) {
      $logins_hash{$LOGIN}{'3.COMMENTS'} =~ s/\n//g;
    }

    #Extended params
    while (my ($k, $v) = each %EXTENDED_STATIC_FIELDS) {
      $logins_hash{$LOGIN}{$k} = $v;
    }

  }

  undef($q);
  return \%logins_hash;
}

#**********************************************************
# Export from Traffpro
#**********************************************************
sub get_traffpro {

  my %fields = (
    'LOGIN'       => 'login',
    'PASSWORD'    => 'key',
    '1.ACTIVATE'  => 'date',
    '1.GID'       => 'id_groups',
    '1.REDUCTION' => 'discount',

    '3.ADDRESS_FLAT'   => 'apartment',
    '3.ADDRESS_STREET' => 'name',
    '3.ADDRESS_BUILD'  => 'house',
    '3.COMMENTS'       => 'comment',
    '3.CONTRACT_ID'    => 'num_contract',
    '3.EMAIL'          => 'email',
    '3.FIO'            => "surname",           # surname - �������,  name - ��� , patronymic - ��������
    '3.PHONE'          => 'phone_mob',
    '3.PASPORT_DATE'   => 'passport_date',
    '3.PASPORT_GRANT'  => 'passport_create',
    '3.PASPORT_NUM'    => 'passport_namber',
    '3.CITY'           => 'name',

    '4.CID'   => 'addr_eth',
    '4.IP'    => 'addr_ip',
    '4.SPEED' => 'speed',
    '4.TP_ID' => 'traff_tarif',

    '5.SUM' => 'traff_money_add',

  );

  my %fields_rev = reverse(%fields);
  my $fields_list = "login, " . join(", \n", values(%fields));

  my $sql = "SELECT cl.login,
 				   pwd.key,
 				   cl.login,
 				   cl.date,
 				   cl.id_groups,
 				   tarif.discount,
 				   addr.apartment,
 				   str.name,
 				   addr.house,
 				   addr.comment,
 				   cont.num_contract,
 				   cont.email,
 				   cont.surname,  #	 cont.surname,	cont.name,  cont.patronymic,
 				   cont.phone_mob,
 				   cont.passport_date,
 				   cont.passport_create,
 				   cont.passport_namber,
 				   city.name,
 				   ca.addr_eth,
 				   ca.addr_ip,
 				   tarif.speed,
 				   ctcm.traff_tarif,
 				   ctcm.traff_money_add
			FROM `clients` AS cl
			LEFT JOIN clients_traff_check_money ctcm ON ( cl.id = ctcm.id )
			LEFT JOIN bus_tarif_plane tarif ON ( tarif.id = ctcm.traff_tarif )
			LEFT JOIN clients_addr ca ON ( ca.id = cl.id )
			LEFT JOIN contacts cont ON ( cont.id = cl.id )
			LEFT JOIN contacts_addr addr ON ( addr.id = cont.addr_registration )
			LEFT JOIN street str ON ( str.id = addr.street )
			LEFT JOIN city city ON ( city.city = str.city_id )
			LEFT JOIN clients_vpn pwd ON ( pwd.id = cl.id )";

  #print $sql;
  if ($DEBUG > 4) {
    print $sql;
    return 0;
  }
  elsif ($DEBUG > 0) {
    print "$sql\n";
  }
  my $q = $db->prepare($sql);
  $q->execute();
  my $query_fields = $q->{NAME};

  my $output      = '';
  my %logins_hash = ();

  while (my @row = $q->fetchrow_array()) {
    my $LOGIN = $row[0];

    for (my $i = 1 ; $i <= $#row ; $i++) {
      if ($DEBUG > 3) {
        print "$i, $query_fields->[$i], |" . $fields_rev{"$query_fields->[$i]"} . "| -> $row[$i] \n";
      }
      print "$i, $query_fields->[$i], |" . $fields_rev{"$query_fields->[$i]"} . "| -> $row[$i] \n";
      $logins_hash{$LOGIN}{ $fields_rev{ $query_fields->[$i] } } = $row[$i] || '';
    }

    if ($logins_hash{$LOGIN}{'6.USERNAME'} && $logins_hash{$LOGIN}{'6.USERNAME'} =~ /(\S+)\@/) {
      $logins_hash{$LOGIN}{'6.USERNAME'} = $1;
    }
    elsif ($logins_hash{$LOGIN}{'3.COMMENTS'}) {
      $logins_hash{$LOGIN}{'3.COMMENTS'} =~ s/\n//g;
    }

    #Extended params
    while (my ($k, $v) = each %EXTENDED_STATIC_FIELDS) {
      $logins_hash{$LOGIN}{$k} = $v;
    }

  }

  undef($q);
  return \%logins_hash;
}

#**********************************************************
# Export from Stargazer
#**********************************************************
sub get_stargazer {

  my %fields = (
    'LOGIN'    => 'login',
    'PASSWORD' => 'Password',
    '1.CREDIT' => 'Credit',
    '1.GID'    => 'StgGroup',

    '3.ADDRESS_STREET' => 'Address',
    '3.COMMENTS'       => 'Note',
    '3.EMAIL'          => 'Email',
    '3.FIO'            => 'RealName',
    '3.PHONE'          => 'Phone',

    '4.IP'    => 'IP',
    '4.TP_ID' => 'Tariff',

    '5.SUM' => 'Cash',

  );

  my %fields_rev = reverse(%fields);
  my $fields_list = "login, " . join(", \n", values(%fields));

  my $sql = "SELECT $fields_list FROM tb_users";

  #print $sql;
  if ($DEBUG > 4) {
    print $sql;
    return 0;
  }
  elsif ($DEBUG > 0) {
    print "$sql\n";
  }
  my $q = $db->prepare($sql);
  $q->execute();
  my $query_fields = $q->{NAME};

  my $output      = '';
  my %logins_hash = ();

  while (my @row = $q->fetchrow_array()) {
    my $LOGIN = $row[0];

    for (my $i = 1 ; $i < $#row ; $i++) {
      if ($DEBUG > 3) {
        print "$i, $query_fields->[$i], " . $fields_rev{"$query_fields->[$i]"} . " -> $row[$i] \n";
      }

      $logins_hash{$LOGIN}{ $fields_rev{ $query_fields->[$i] } } = $row[$i];
    }

    if ($logins_hash{$LOGIN}{'6.USERNAME'} && $logins_hash{$LOGIN}{'6.USERNAME'} =~ /(\S+)\@/) {
      $logins_hash{$LOGIN}{'6.USERNAME'} = $1;
    }
    elsif ($logins_hash{$LOGIN}{'3.COMMENTS'}) {
      $logins_hash{$LOGIN}{'3.COMMENTS'} =~ s/\n//g;
    }

    #Extended params
    while (my ($k, $v) = each %EXTENDED_STATIC_FIELDS) {
      $logins_hash{$LOGIN}{$k} = $v;
    }

  }

  undef($q);
  return \%logins_hash;
}

#**********************************************************
# Export from Stargazer
#**********************************************************
sub get_stargazer_pg {

  my %fields = (
    'LOGIN'    => 'name',
    'PASSWORD' => 'passwd',
    '1.CREDIT' => 'credit',

    #  '1.GID'             => 'grp',
    '3.ADDRESS_STREET' => 'address',
    '3.COMMENTS'       => 'note',

    #  '3.EMAIL'           => 'email',
    '3.FIO'   => 'real_name',
    '3.PHONE' => 'phone',
    '4.TP_ID' => 'fk_tariff',
    '5.SUM'   => 'cash',
    '4.IP'    => 'ip'

    #tb_users.pk_user - ��������� ���� ������������
    #tb_users.last_cash_add - ����� ���������� ����������
    #tb_users.last_cash_add_time - ���� ���������� ����������

  );

  my %fields_rev = reverse(%fields);
  my $fields_list = "name, " . join(", \n", values(%fields));

  my $sql = "SELECT $fields_list
  FROM tb_users u
  LEFT JOIN tb_allowed_ip ip ON (ip.fk_user=u.pk_user)";

  #print $sql;
  if ($DEBUG > 4) {
    print $sql;
    return 0;
  }
  elsif ($DEBUG > 0) {
    print "$sql\n";
  }
  my $q = $db->prepare($sql);
  $q->execute();
  my $query_fields = $q->{NAME};

  my $output      = '';
  my %logins_hash = ();

  while (my @row = $q->fetchrow_array()) {
    my $LOGIN = $row[0];

    for (my $i = 1 ; $i < $#row ; $i++) {
      if ($DEBUG > 3) {
        print "$i, $query_fields->[$i], " . $fields_rev{"$query_fields->[$i]"} . " -> $row[$i] \n";
      }

      $logins_hash{$LOGIN}{ $fields_rev{ $query_fields->[$i] } } = $row[$i];
    }

    if ($logins_hash{$LOGIN}{'6.USERNAME'} && $logins_hash{$LOGIN}{'6.USERNAME'} =~ /(\S+)\@/) {
      $logins_hash{$LOGIN}{'6.USERNAME'} = $1;
    }
    elsif ($logins_hash{$LOGIN}{'3.COMMENTS'}) {
      $logins_hash{$LOGIN}{'3.COMMENTS'} =~ s/\n//g;
    }

    #Extended params
    while (my ($k, $v) = each %EXTENDED_STATIC_FIELDS) {
      $logins_hash{$LOGIN}{$k} = $v;
    }

  }

  undef($q);
  return \%logins_hash;
}

#**********************************************************
# Export from  nousaibot billing
#**********************************************************
sub get_bbilling {

  my %fields = (
    'LOGIN'    => 'CardNumber',
    'PASSWORD' => 'PIN',

    '3._serialnumber'   => 'SerialNumber',
    '3._tariffplanname' => 'TariffPlanName',
    '3._subscribername' => 'SubscriberName',

    '4.TP_ID' => 'TariffPlanNameID',

    '5.SUM' => 'Saldo',

  );

  my %fields_rev = reverse(%fields);
  my $fields_list = "CardNumber, " . join(", \n", values(%fields));

  my $sql = "SELECT $fields_list FROM data";

  #print $sql;
  if ($DEBUG > 4) {
    print $sql;
    return 0;
  }
  elsif ($DEBUG > 0) {
    print "$sql\n";
  }
  my $q = $db->prepare($sql);
  $q->execute();
  my $query_fields = $q->{NAME};

  my $output      = '';
  my %logins_hash = ();

  while (my @row = $q->fetchrow_array()) {
    my $LOGIN = $row[0];

    for (my $i = 1 ; $i < $#row ; $i++) {
      if ($DEBUG > 3) {
        print "$i, $query_fields->[$i], " . $fields_rev{"$query_fields->[$i]"} . " -> $row[$i] \n";
      }

      $logins_hash{$LOGIN}{ $fields_rev{ $query_fields->[$i] } } = $row[$i];
    }

    if ($logins_hash{$LOGIN}{'6.USERNAME'} && $logins_hash{$LOGIN}{'6.USERNAME'} =~ /(\S+)\@/) {
      $logins_hash{$LOGIN}{'6.USERNAME'} = $1;
    }
    elsif ($logins_hash{$LOGIN}{'3.COMMENTS'}) {
      $logins_hash{$LOGIN}{'3.COMMENTS'} =~ s/\n//g;
    }

    #Extended params
    while (my ($k, $v) = each %EXTENDED_STATIC_FIELDS) {
      $logins_hash{$LOGIN}{$k} = $v;
    }

  }

  undef($q);
  return \%logins_hash;
}

#**********************************************************
# Export easyhotspot
#**********************************************************
sub get_easyhotspot {

  my %fields = (
    'LOGIN'    => 'username',
    'PASSWORD' => 'password',
    '4.TP_ID'  => 'id',
  );

  my %fields_rev = reverse(%fields);

  #my $fields_list = "username, password ". join(", \n", values(%fields));

  my $sql = "SELECT  v.username,
 					v.password,
 					v.username,
 				   	v.password,
 				   	b.id
			FROM `voucher` AS v
			LEFT JOIN billingplan b ON ( b.name = v.billingplan )";

  #print $sql;
  if ($DEBUG > 4) {
    print $sql;
    return 0;
  }
  elsif ($DEBUG > 0) {
    print "$sql\n";
  }
  my $q = $db->prepare($sql);
  $q->execute();
  my $query_fields = $q->{NAME};

  my $output      = '';
  my %logins_hash = ();

  while (my @row = $q->fetchrow_array()) {
    my $LOGIN = $row[0];

    for (my $i = 1 ; $i <= $#row ; $i++) {
      if ($DEBUG > 3) {
        print "$i, $query_fields->[$i], |" . $fields_rev{"$query_fields->[$i]"} . "| -> $row[$i] \n";
      }
      $logins_hash{$LOGIN}{ $fields_rev{ $query_fields->[$i] } } = $row[$i] || '';
    }

    if ($logins_hash{$LOGIN}{'6.USERNAME'} && $logins_hash{$LOGIN}{'6.USERNAME'} =~ /(\S+)\@/) {
      $logins_hash{$LOGIN}{'6.USERNAME'} = $1;
    }
    elsif ($logins_hash{$LOGIN}{'3.COMMENTS'}) {
      $logins_hash{$LOGIN}{'3.COMMENTS'} =~ s/\n//g;
    }

    #Extended params
    while (my ($k, $v) = each %EXTENDED_STATIC_FIELDS) {
      $logins_hash{$LOGIN}{$k} = $v;
    }

  }

  undef($q);
  return \%logins_hash;
}

#**********************************************************
# Export from lms
# http://www.lms.org.pl/doc_en/devel-db.html
# http://www.lms.org.pl
#**********************************************************
sub get_lms {

  my %fields = (
    'LOGIN'    => 'id',
    'PASSWORD' => 'pin',

    '1.GID'          => 'customergroupid',
    '1.REGISTRATION' => 'FROM_UNIXTIME(c.creationdate)',
    '1.DISABLE'      => 'deleted',

    '3.ADDRESS_STREET' => 'if(c.address!=\'\', c.address, \'\')',

    '3.COMMENTS' => 'if(c.message!=\'\', c.message, \'\')',
    '3.EMAIL'    => 'if(c.email!=\'\', c.email, \'\')',
    '3.FIO'      => 'if(c.lastname!=\'\', c.lastname, \'\')',

    '3.PHONE' => 'if(c.phone1!=\'\', c.phone1, \'\')',
    '3.ZIP'   => 'if(c.zip!=\'\', c.zip, \'\')',
    '3.CITY ' => 'if(c.city!=\'\', c.city, \'\')',
    '4.TP_ID' => 'tariffplan',
    '5.SUM'   => 'if((SELECT SUM(value) FROM cash WHERE customerid=c.id)!=\'\', (SELECT SUM(value) FROM cash WHERE customerid=c.id), \'\')',

  );

  my %fields_rev = reverse(%fields);

  #my $fields_list = "id, pin". join(", \n", values(%fields));

  my $sql = "select 	c.id as id,
 					c.id as id,
 					c.pin as pin,
 					if(ca.customergroupid!=\'\', ca.customergroupid, \'\') as customergroupid,
 					FROM_UNIXTIME(c.creationdate),
 					c.deleted as deleted,
 					if(c.address!=\'\', c.address, \'\'),
 					if(c.message!=\'\', c.message, \'\'),
 					if(c.email!=\'\', c.email, \'\'),
 					if(c.lastname!=\'\', c.lastname, \'\'),
 					if(c.phone1!=\'\', c.phone1, \'\'),
 					if(c.zip!=\'\', c.zip, \'\'),
 					if(c.city!=\'\', c.city, \'\'),
 					if(a.tariffid!=\'\', a.tariffid, \'\')  as tariffplan,
 					if((SELECT SUM(value) FROM cash WHERE customerid=c.id)!=\'\', (SELECT SUM(value) FROM cash WHERE customerid=c.id), \'\')

  FROM (customers c)
  LEFT JOIN assignments a ON (a.customerid=c.id)
  LEFT JOIN customerassignments ca ON (ca.customerid=c.id)

  GROUP BY c.id
  ORDER BY 1";

  if ($DEBUG > 5) {
    print $sql;
    return 0;
  }
  elsif ($DEBUG > 0) {
    print "$sql\n";
  }
  my $q = $db->prepare($sql);
  $q->execute();
  my $query_fields = $q->{NAME};

  my $output      = '';
  my %logins_hash = ();

  while (my @row = $q->fetchrow_array()) {
    my $LOGIN = $row[0];

    for (my $i = 1 ; $i <= $#row ; $i++) {
      if ($DEBUG > 3) {
        print "$i, $query_fields->[$i], " . $fields_rev{"$query_fields->[$i]"} . " -> $row[$i] \n";
      }

      $logins_hash{$LOGIN}{ $fields_rev{ $query_fields->[$i] } } = $row[$i];
    }

    if ((!$logins_hash{$LOGIN}{'5.SUM'})) {
      $logins_hash{$LOGIN}{'5.SUM'} = '0.00';
    }

    if ($logins_hash{$LOGIN}{'6.USERNAME'} && $logins_hash{$LOGIN}{'6.USERNAME'} =~ /(\S+)\@/) {
      $logins_hash{$LOGIN}{'6.USERNAME'} = $1;
    }
    elsif ($logins_hash{$LOGIN}{'3.COMMENTS'}) {
      $logins_hash{$LOGIN}{'3.COMMENTS'} =~ s/\n//g;
    }

    #Extended params
    while (my ($k, $v) = each %EXTENDED_STATIC_FIELDS) {
      $logins_hash{$LOGIN}{$k} = $v;
    }

  }

  undef($q);
  return \%logins_hash;
}

#**********************************************************
# Export lms nodes
# http://www.lms.org.pl/doc_en/devel-db.html
# http://www.lms.org.pl
#**********************************************************
sub get_lms_nodes {

  my $sql = "select ownerid, inet_ntoa(ipaddr), mac from nodes";

  if ($DEBUG > 0) {
    print "$sql\n";
  }
  my $q = $db->prepare($sql);
  $q->execute();
  my $query_fields = $q->{NAME};

  while (my @row = $q->fetchrow_array()) {
    print "$row[0]\t$row[1]\t$row[2]\n";
  }
  exit();
}

#**********************************************************
#
#**********************************************************
sub get_odbc {

  #, , , , , , connspeed__id

  my %fields = (
    'LOGIN'    => 'user__login',
    'PASSWORD' => 'user__pass',

    #  '1.ACTIVATE'     => 'activated',
    #  '1.EXPIRE' 	     => 'expired',
    #  '1.COMPANY_ID'   => '',
    '1.CREDIT_DATE' => 'user__createdt',
    '1.GID'         => 'group__id',

    #  '1.REDUCTION'    => '',
    #'1.REGISTRATION' => 'DATE_FORMAT(FROM_UNIXTIME(reg_date), \'%Y-%m-%d\')',
    '4.DISABLE' => 'user_state__id',
    '1.DELETED' => 'user__deletedt',

    #  '3.ADDRESS_FLAT'   => '',
    #  '3.ADDRESS_STREET' => 'actual_address',
    #  '3.ADDRESS_BUILD'  => '',
    #  '3.COMMENTS'       => '',
    #  '3.CONTRACT_ID' 	 => '',
    #'3.EMAIL' => 'email',
    #'3.FIO'   => 'full_name',
    #  '3.PHONE'          => 'phone',
    #  '4.CID'            => '',
    #  '4.FILTER_ID'      => '',
    '4.IP' => 'user__framed_ip_address',

    #  '4.NETMASK'        => '\'255.255.255.255\'',
    #  '4.SIMULTANEONSLY' => 'simultaneous_use',
    #  '4.SPEED'          => 'speed',
    '4.TP_ID' => 'tariff__id',

    #  '4.CALLBACK'       => 'allow_callback',

    #'5.SUM' => 'bill',

    #  '5.DESCRIBE' 	     => "'Migration'",
    #  '5.ER'             => undef,
    #  '5.EXT_ID'         => undef,

    #  '6.USERNAME'       => 'email',
    #  '6.DOMAINS_SEL'     => $email_domain_id || 0,
    #  '6.COMMENTS'        => '',
    #  '6.MAILS_LIMIT'	    => 0,
    #  '6.BOX_SIZE'	      => 0,
    #  '6.ANTIVIRUS'	      => 0,
    #  '6.ANTISPAM'	      => 0,
    #  '6.DISABLE'	        => 0,
    #  '6.EXPIRE'	        => undef,
    #  '6.PASSWORD'	      => 'email_pass',
  );

  my %fields_rev = reverse(%fields);
  my $fields_list = join(",\n ", values(%fields));

  my $sql = "SELECT $fields_list FROM users";
  print "$sql\n" if ($DEBUG > 1);

  my $q = $db->prepare($sql);
  $q->execute();
  my $query_fields = $q->{NAME};

  my $output      = '';
  my %logins_hash = ();

  while (my $row = $q->fetchrow_hashref()) {
    my $LOGIN = $row->{ $fields{LOGIN} };
    if ($DEBUG > 3) {
      print "$LOGIN ============= \n";
    }

    # Field name
    while (my ($k, $v) = each %$row) {
      if ($DEBUG > 3) {
        print "$k, $fields_rev{$k} -> " . ((defined($v)) ? $v : '') . "\n";
      }

      $logins_hash{$LOGIN}{ $fields_rev{$k} } = $v;
    }

    if ($logins_hash{$LOGIN}{'1.CREDIT'} && $logins_hash{$LOGIN}{'1.CREDIT'} =~ /(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/) {
      $logins_hash{$LOGIN}{'1.CREDIT'} = $1;
    }

    #Extended params
    while (my ($k, $v) = each %EXTENDED_STATIC_FIELDS) {
      $logins_hash{$LOGIN}{$k} = $v;
    }

  }

  undef($q);
  return \%logins_hash;

}

#**********************************************************

=head2 get_carbon4() - Import from Carbon 4

=cut

#**********************************************************
sub get_carbon4 {
  my %fields = (
    'LOGIN'      => 'LOGIN',
    'PASSWORD'   => 'PSW',
    '1.ACTIVATE' => 'ACTIVATE_DATE',
    '1.GID'      => 'PARID',
    '1.DISABLE'  => 'DISABLED',

    #    '1.REDUCTION' => 'discount',

    '3.ADDRESS_FLAT'   => 'A_HOME_NUMBER',
    '3.ADDRESS_STREET' => 'STREET',
    '3.ADDRESS_BUILD'  => 'S_NUMBER',

    #    '3.COMMENTS'       => 'comment',
    #    '3.CONTRACT_ID'    => 'num_contract',
    '3.EMAIL'         => 'EMAIL',
    '3.FIO'           => 'IDENTIFY',
    '3.PHONE'         => 'PHONE',
    '3.PASPORT_DATE'  => 'PASPORT_DATE',
    '3.PASPORT_GRANT' => 'PASPORT_GRANT',
    '3.PASPORT_NUM'   => 'PASPORT_NUM',
    '3.CITY'          => 'CITY',

    '4.CID'   => 'MAC',
    '4.IP'    => 'IP',
    '4.SPEED' => 'LIMIT',
    '4.TP_ID' => 'TARIFF_NO',

    '5.SUM' => 'OSTATOK',

  );

  my %fields_rev = reverse(%fields);
  my $fields_list = "login, " . join(", \n", values(%fields));

  my %attribute_type_id_for = (
    PHONE       => 1,
    PASPORT_NUM => 13,

    #    PASPORT_SER => 15,
    PASPORT_BY   => 16,
    PASPORT_DATE => 17,
  );

  my $sql = "SELECT USERS.LOGIN,
                    USERS.PSW,
                    USERS.ENABLED AS ENABLED,
                    0 AS DISABLED,
                    USERS.ID,
                    USERS.ACTIVATE_DATE,
                    USERS.PARID,
                    USERS.A_HOME_NUMBER,
                    HOMES.CITY,
                    HOMES.STREET,
                    HOMES.S_NUMBER,
                    USERS.EMAIL,
                    USERS.IDENTIFY,
                    USERS.MAC,
                    USERS.IP,
                    USERS.OSTATOK,
                    (SELECT ATTRIBUTE_VALUE FROM ATTRIBUTE_VALUES WHERE USER_ID=USERS.ID AND ATTRIBUTE_ID=$attribute_type_id_for{PHONE}) AS PHONE,
    (SELECT ATTRIBUTE_VALUE FROM ATTRIBUTE_VALUES WHERE USER_ID=USERS.ID AND ATTRIBUTE_ID=$attribute_type_id_for{PASPORT_NUM}) AS PASPORT_NUM,
    (SELECT ATTRIBUTE_VALUE FROM ATTRIBUTE_VALUES WHERE USER_ID=USERS.ID AND ATTRIBUTE_ID=$attribute_type_id_for{PASPORT_BY}) AS PASPORT_GRANT,
    (SELECT ATTRIBUTE_VALUE FROM ATTRIBUTE_VALUES WHERE USER_ID=USERS.ID AND ATTRIBUTE_ID=$attribute_type_id_for{PASPORT_DATE}) AS PASPORT_DATE

     FROM USERS
     LEFT JOIN HOMES ON (HOMES.ID = USERS.HOME_ID);
          ";

  #print $sql;
  if ($DEBUG > 4) {
    print $sql;
    return 0;
  }
  elsif ($DEBUG > 0) {
    print "$sql\n";
  }
  my DBI::st $q = $db->prepare($sql);
  $q->execute();

  my $users_list = $q->fetchall_hashref('ID');

  my %without_logins = ();
  foreach my $user (values %{$users_list}) {

    # Translating carbon 'ENABLED' to abills 'disabled' attr
    $user->{DISABLED} = !$user->{ENABLED};

    if (!$user->{LOGIN}) {
      $without_logins{ $user->{ID} } = $user;

      #      print "!!! User $user->{ID}( $user->{IDENTIFY}  ) don't have login. \n Will not be included in results \n";
      delete $users_list->{ $user->{ID} };
    }
  }

  # DB charset is CP1251, and we are working in UTF8
  # so need to convert some of columns got from DB
  eval { require Encode; };
  if (@!) {
    print "Please install 'Encode' perl module\n";

    #    print "Manual: http://abills.net.ua/wiki/doku.php/abills:docs:manual:soft:perl_odbc \n";
    exit;
  }
  Encode->import();

  my $convert_in_hashref_sub = sub {

    my ($list, $columns_to_convert) = @_;
    foreach my $row (@{$list}) {
      foreach my $column_name (@{$columns_to_convert}) {
        $row->{$column_name} = Encode::encode('utf8', Encode::decode('cp1251', $row->{$column_name}));
      }
    }

    return $list;
  };

  my @columns_can_contain_cyrillic_values = qw/ IDENTIFY PASPORT_GRANT PSW /;
  $users_list = &{$convert_in_hashref_sub}([ values %{$users_list} ], \@columns_can_contain_cyrillic_values);

  foreach my $user (@{$users_list}) {
    if (exists $without_logins{ $user->{PARID} }) {

      #      print "$user->{IDENTIFY} is probably a group \n";
    }
  }

  # Show result
  my $divider = "\t";
  foreach my $user_row (@{$users_list}) {

    # print login, password
    my $login = $user_row->{LOGIN};
    my $password = $user_row->{PSW} || $DEFAULT_PASSWORD;

    next if ($user_row->{LOGIN} =~ /\d+\-\d+/);

    delete $user_row->{LOGIN};
    delete $user_row->{PSW};

    my @attributes_row = ();

    # Login and password are going as first two columns
    push(@attributes_row, ($login, $password));

    # Saving all other attributes in sorted by attr order
    foreach my $attribute_name (sort keys %fields) {
      my $attr_value = $user_row->{ $fields{$attribute_name} };
      next if (!defined($attr_value) || $attr_value eq '' || $attr_value !~ /[0-9a-zA-Zа-яА-Я_]+/);
      push(@attributes_row, "$attribute_name=" . '"' . $attr_value . '"');
    }

    # Show result
    print join($divider, @attributes_row);

    # Next line
    print "\n";
  }

  exit;

}

#**********************************************************

=head2 sync_deposit($update_list) - Syncing deposits from file

  Arguments:
    $update_list - array of hash_ref
    {
      LOGIN   - user id,
      NEW_SUM - new balance value
    }

=cut

#**********************************************************
sub sync_deposit {
  my ($update_list) = @_;

  foreach my $user_hash (values %{$update_list}) {
    my $login   = $user_hash->{LOGIN};
    my $new_sum = $user_hash->{NEW_SUM};

    my $sql = "UPDATE bills SET deposit= ? WHERE uid=(SELECT uid FROM users WHERE id= ? )";

    my $q = $db->prepare($sql);

    $q->execute($new_sum, $login);

    print 'Changed ' . $login . ' deposit to ' . $new_sum . "\n";
  }

}

1