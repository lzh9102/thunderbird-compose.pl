#!/usr/bin/perl

# configuration

my $tabwidth = 3;

# ---- end of configuration ----

use strict;
use warnings;
use File::Temp;
use Text::Markdown 'markdown';
use Term::UI;
use Term::ReadLine;

my $term = Term::ReadLine->new();

sub write_default_fields() {
	open TF, ">", $_[0];
	print TF <<EOF
TO: 
CC: 
SUBJECT: 
ATTACHMENT: 
----- body below -----
EOF
	;
	close TF;
}

sub encode_body() {
	my $text = shift;
	my $html = markdown($text, {tab_width => $tabwidth});
	$html =~ s/\\\n//g; # concatenate lines separated with \<newline>
	$html =~ s/\n/ /g; # join lines
	return $html;
}

my $tmpfile;
if (!@ARGV) {
	$tmpfile = File::Temp->new();
	&write_default_fields($tmpfile);
} else {
	$tmpfile = $ARGV[0];
	&write_default_fields($tmpfile) unless (-e $tmpfile);
}

# call vim to edit file
system('vim', $tmpfile);

# read tmpfile back and process it
open TF, "<", $tmpfile;
my %args = ();

while (<TF>) { # read header
	my $line = $_;
	if ($line =~ /^([a-zA-Z]+):\s*(.*)$/) {
		my $key = lc($1);
		my $value = $2;
		$value =~ s/\s+$//; # remove trailing spaces
		$value =~ s/\"/\\"/g;
		$args{$key} = $value;
	} else {
		last;
	}
}
my $body = "";
while (<TF>) { # read body
	$body .= $_;
}
close TF;

# check recepients
if ($args{"to"} =~ /^\s*$/) {
	print "Recepients not specified.\n";
	exit 1;
}

my $arg = "";
for my $key (keys %args) {
	$arg .= "$key='" . $args{$key} . "',";
}
$arg .= "body=" . &encode_body($body);

# invoke thunderbird
if ($term->ask_yn(
		prompt => "E-mail is ready. Open Thundebird compose window?",
		default => 'y')) {
	system('thunderbird', '--compose', $arg);
}