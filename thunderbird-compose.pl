#!/usr/bin/perl

# configuration

my $tabwidth = 3;

# ---- end of configuration ----

use strict;
use warnings;
use Cwd 'abs_path';
use File::Temp;
use File::Copy 'copy';
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

sub path_to_url() {
	return "file://" . abs_path($_[0]);
}

sub encode_body() {
	my $text = shift;
	my $html = markdown($text, {tab_width => $tabwidth});
	$html =~ s/\\\n//g; # concatenate lines separated with \<newline>
	$html =~ s/\n/ /g; # join lines
	return $html;
}

my $filename;
my $file_is_temp = 1;
if (!@ARGV) {
	$filename = File::Temp->new();
	&write_default_fields($filename);
} else {
	$filename = $ARGV[0];
	&write_default_fields($filename) unless (-e $filename);
	$file_is_temp = 0;
}

# call vim to edit file
system('vim', $filename);

# read tmpfile back and process it
open TF, "<", $filename;
my %args = ();

while (<TF>) { # read header
	my $line = $_;
	if ($line =~ /^([a-zA-Z]+):\s*(.*)$/) {
		my $key = lc($1);
		my $value = $2;
		$value =~ s/\s+$//; # remove trailing spaces
		$value =~ s/\"/\\"/g;
		$args{$key} = $value;
	} elsif ($line =~ /^---+/) {
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
} else {
	# encode body and convert paths to url
	my $body_html = &encode_body($body);
	$body_html =~ s {(['"< ]src=['"])([^'"]+)} {$1@{[&path_to_url($2)]}};

	# encode attachment paths as url
	if (exists $args{"attachment"}) {
		my @attachments = ();
		@attachments = map { &path_to_url($_) } split(",", $args{"attachment"});
		$args{"attachment"} = join(", ", @attachments);
	}

	# build command line argument string passed to thunderbird
	my $arg = "";
	for my $key (keys %args) {
		$arg .= "$key='" . $args{$key} . "',";
	}
	$arg .= "body=" . $body_html;

	# invoke thunderbird
	if ($term->ask_yn(
			prompt => "E-mail is ready. Open Thundebird compose window?",
			default => 'y')) {
		system('thunderbird', '--compose', $arg);
	}
}

# prompt to save file
if ($file_is_temp && $term->ask_yn(
		prompt => "Do you want to save the e-mail to a file?",
		default => 'y')) {
	my $save_filename = $term->readline("Enter a filename: ");
	copy($filename, $save_filename);
}
