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
use HTML::Clean;
use Term::UI;
use Term::ReadLine;
use Getopt::Long;

my $term = Term::ReadLine->new();

sub write_default_fields() {
	my %args = @_;
	open TF, ">", $args{filename};
	print TF "TO: " . $args{recepient} . "\n";
	print TF "CC: " . $args{cc} . "\n";
	print TF "SUBJECT: " . $args{subject} . "\n";
	print TF "ATTACHMENT: " . $args{attachment} . "\n";
	print TF "----- body (markdown syntax) -----\n\n";
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
	# minify html code
	my $h = new HTML::Clean(\$html);
	$h->strip();
	return $html;
}

sub create_tmpfile() {
	my %args = @_;
	my $filename = File::Temp->new();
	$args{filename} = $filename;
	&write_default_fields(%args);
	return $filename;
}

sub read_tmpfile() {
	my $filename = shift;
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
	$args{body} = $body;
	return %args;
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

my $filename = &create_tmpfile(
	subject => $opt_subject,
	recepient => join(',', @opt_recepients),
	attachment => join(',', @opt_attachments),
	cc => join(',', @opt_cc_list)
);
my $file_mtime = stat($filename)->mtime;

# call vim to edit file
system('vim', $filename);

# exit if file not modified
if (stat($filename)->mtime == $file_mtime) {
	print "File not modified.\n";
	exit 1;
}

# read tmpfile back and process it
my %args = &read_tmpfile($filename);

# check recepients
if ($args{"to"} =~ /^\s*$/) {
	print "Recepients not specified.\n";
} else {
	# encode attachment paths as url
	if (exists $args{attachment}) {
		my @attachments = ();
		@attachments = map { &path_to_url($_) } split(",", $args{attachment});
		$args{attachment} = join(", ", @attachments);
	}

	# build command line argument string passed to thunderbird
	my $arg = "";
	for my $key (keys %args) {
		if ($key ne "body") {
			$arg .= "$key='" . $args{$key} . "',";
		}
	}
	$arg .= "body=" . &encode_body($args{body});

	# invoke thunderbird
	if ($term->ask_yn(
			prompt => "E-mail is ready. Open Thundebird compose window?",
			default => 'y')) {
		system('thunderbird', '--compose', $arg);
	}
}

# prompt to save file
if ($term->ask_yn(
		prompt => "Save the modified content to a file?",
		default => 'y')) {
	while () {
		my $save_filename = $term->readline("Enter a filename: ");
		last if (copy($filename, $save_filename));
		print "Failed to save the file to $save_filename\n";
	}
}
