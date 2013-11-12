#!/usr/bin/perl

# configuration

my $tabwidth = 3;

# ---- end of configuration ----

use strict;
use warnings;
use Cwd 'abs_path';
use File::Temp;
use File::Copy 'copy';
use File::stat;
use Text::Markdown 'markdown';
use HTML::Packer;
use Term::UI;
use Term::ReadLine;
use Getopt::Long;

my $term = Term::ReadLine->new();
my $packer = HTML::Packer->init();

sub write_default_fields() {
	my $args_ref = shift;
	my %args = %$args_ref;
	open TF, ">", $args{filename};
	print TF "TO: " . $args{recepient} . "\n";
	print TF "CC: " . $args{cc} . "\n";
	print TF "SUBJECT: " . $args{subject} . "\n";
	print TF "ATTACHMENT: " . $args{attachment} . "\n";
	print TF "----- body (markdown syntax) -----\n";
	close TF;
}

sub path_to_url() {
	return "file://" . abs_path($_[0]);
}

sub encode_body() {
	my $text = shift;
	# replace file path to url
	$text =~ s {!\[([^\]]*)\]\(([^\)]*)\)} {![$1](@{[&path_to_url($2)]})};
	# concatenate lines separated with \<newline>
	$text =~ s/\\\n//g;
	# convert markdown to html
	my $html = markdown($text, {tab_width => $tabwidth});
	$packer->minify(\$html, {remove_newlines => 1});
	return $html;
}

# parse options
my $opt_subject = "";
my @opt_attachments = ();
my @opt_cc_list = ();

GetOptions(
	"s|subject=s" => \$opt_subject,
	"a|attachment=s" => \@opt_attachments,
	"c|cc=s" => \@opt_cc_list
);

# allow specifying attachments in comma-separated list (ex. -a file1,file2)
@opt_attachments = split(',', join(',', @opt_attachments));
@opt_cc_list = split(',', join(',', @opt_cc_list));

# build recepient list
my @opt_recepients = @ARGV;

# create temp file
my $filename;
my $file_is_temp = 1;
$filename = File::Temp->new();
&write_default_fields({
	filename => $filename,
	subject => $opt_subject,
	recepient => join(',', @opt_recepients),
	attachment => join(',', @opt_attachments),
	cc => join(',', @opt_cc_list)
});
my $file_mtime = stat($filename)->mtime;

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
	$arg .= "body=" . &encode_body($body);

	# invoke thunderbird
	if ($term->ask_yn(
			prompt => "E-mail is ready. Open Thundebird compose window?",
			default => 'y')) {
		system('thunderbird', '--compose', $arg);
	}
}

# prompt to save file
if ($file_is_temp && stat($filename)->mtime != $file_mtime && $term->ask_yn(
		prompt => "Your modifications will be lost. Save the content to a file?",
		default => 'y')) {
	while () {
		my $save_filename = $term->readline("Enter a filename: ");
		last if (copy($filename, $save_filename));
		print "Failed to save the file to $save_filename\n";
	}
}
