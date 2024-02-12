#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Cwd 'abs_path';
use Getopt::Long qw(GetOptions);
use File::Basename;
use MIME::Lite;

my $subject;
my $email;
my $content;

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

options:

  -s  <string> Subject
  -c  <string> Email content
  -e  <string> Email addresses
  
__EOUSAGE__



GetOptions (
  's=s' => \$subject,
  'c=s' => \$content,
  'e=s' => \$email
);

if (!$subject || !$content || !$email) {
    die "Required argurments missing\n$usage";
}

my $sender    = 'oncogenomics@mail.nih.gov';
my $mime = MIME::Lite->new(
	    'From'    => $sender,
	    'To'      => $email,
	    'Subject' => $subject,
	    'Type'    => 'text/html',
	    'Data'    => $content,
);

$mime->send();

