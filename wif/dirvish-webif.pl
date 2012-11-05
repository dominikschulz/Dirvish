#!/usr/bin/perl -w
# dirvish
# 1.3.X series
# Copyright 2009 by the dirvish project
# http://www.dirvish.org
#
# Last Revision   : $Rev: 654 $
# Revision date   : $Date: 2009-02-05 22:10:21 +0100 (Do, 05 Feb 2009) $
# Last Changed by : $Author: tex $
# Stored as       : $HeadURL: https://secure.id-schulz.info/svn/tex/priv/dirvish_1_3_1/wif/dirvish-webif.pl $
#
#########################################################################
#                                                         				#
#	Licensed under the Open Software License version 2.0				#
#                                                         				#
#	This program is free software; you can redistribute it				#
#	and/or modify it under the terms of the Open Software				#
#	License, version 2.0 by Lauwrence E. Rosen.							#
#                                                         				#
#	This program is distributed in the hope that it will be				#
#	useful, but WITHOUT ANY WARRANTY; without even the implied			#
#	warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR				#
#	PURPOSE.  See the Open Software License for details.				#
#                                                         				#
#########################################################################
#
# This is a web-based configuration and control frontend for dirvish.
# http://snippets.dzone.com/posts/show/257

# Includes
use lib "../.";

use warnings;
use strict;
use HTTP::Daemon;
use HTTP::Status;
use Dirvish;
use Data::Dumper;
use Thread qw(async);

# Initialisation
my $template = `cat dirvish.html`;
# initialize the %$Options hash
my $Options = reset_options( \&usage, @ARGV);
load_master_config('', $Options); 

#dump_config($Options);

print "Port: $ARGV[0]\n";

# Setup Webserver
my $d = HTTP::Daemon->new(
	LocalAddr	=> 'localhost',
	LocalPort	=> $ARGV[0],
) || die;

print "Please contact me at: <URL:", $d->url, ">\n";
CONNECTION: while (my $c = $d->accept) {
	my $t = async {
		REQUEST: while (my $r = $c->get_request) {
			#print "Thread: ".Thread->self->tid()." - Request: ".$r->url." - Path: - ".$r->url->path."\n";
			my $resp = get_response($c,$r);
        	$c->send_response($resp) if $resp;
    	}
    	$c->close;
    	undef($c);
	};
}

END {
	$d->shutdown();
}

# Subs
sub get_response {
	my $c = shift; # connection
	my $r = shift; # request
	my $body = $template;
	# Top-Navigation
	my $topnav = '<li><a href="/browse/">Browse</a></li>';
	$topnav .= '<li><a href="/search">Search</a></li>';
	$topnav .= '<li><a href="/settings">Settings</a></li>';
	$topnav .= "<li>Status: ";
	my $expire_pidfile = $$Options{'pidfile'};
	$expire_pidfile =~ s/\/dirvish[.]pid/\/dirvish-expire.pid/;
	if(-f $$Options{'pidfile'} || -f $expire_pidfile) {
		my $pid = `cat $$Options{'pidfile'}`;
		chomp($pid);
		# TODO check if it is really running, see check_pidfile
		$topnav .= 'Running - <a href="/stop_backup">Stop Backup</a>';
	} else {
		$topnav .= 'Idle - <a href="/start_backup">Start Backup</a>';
	}
	$topnav .= "</li>\n";
	# Left-Navigation
	my $left_title = "Browse";
	my $left_nav;
	foreach my $vault (@{$$Options{'Runall'}}) {
		$left_nav .= '<li>Vault <a href="/browse/'.$vault.'/">'.$vault.'</a></li>';
	}
	# Content Default
	my $content_title = "Welcome to Dirivsh";
	my $content_body = "&nbsp;";
	# Content
	my $path = $r->url->path;
	$path = url_decode($path);
	$path =~ s/[.][.]//g; # remove double dots
	$path =~ s/(\/\s*\/)+/\//g; # remove repeated-slashes
	my @path = split("/",$path);
	if($path =~ m/^\/settings/) {
		# TODO handle save settings
		$content_title = "Settings";
		$content_body .= '<form action="/settings" method="POST">';
		$content_body .= '<input type="hidden" name="save" value="1" /><br />';
		$content_body .= 'Bank: <input type="text" value="'.$$Options{'bank'}[0].'" name="bank" /><br />'; # TODO muliple banks
		$content_body .= 'Index-Type: <input type="text" value="'.$$Options{'index'}.'" name="index" /><br />'; # TODO select (none,gzip,bzip2)
		$content_body .= 'Ionice: <input type="text" value="'.$$Options{'ionice'}.'" name="ionice" /><br />'; # TODO select (0-7)
		$content_body .= 'Nice: <input type="text" value="'.$$Options{'nice'}.'" name="nice" /><br />'; # TODO select (0-19)
		$content_body .= 'Rsh: <input type="text" value="'.$$Options{'rsh'}.'" name="rsh" /><br />';
		$content_body .= '<input type="submit" name="Submit" value="Submit" />';
		$content_body .= '</form>';
	} elsif($path =~ m/^\/browse/) {
		# show file browser
		shift(@path); # (empty) root
		shift(@path); # action
		my $vault = shift(@path); # vault
		if(!$vault) {
			$content_title = "Browsing Vaults";
			$content_body = "";
			# show list of vaults and return
			foreach my $vault (@{$$Options{'Runall'}}) {
				$content_body .= 'Vault <a href="/browse/'.$vault.'/">'.$vault.'</a><br />';
			}
			goto BODY;
		}
		# TODO find correct bank
    	my $bank = "";
	    foreach my $bankc (@{$$Options{bank}})
    	{
        	if (-d "$bankc/$vault")
        	{
        		$bank = $bankc;
	            last;
        	}
    	}
    	if(!$bank) {
    		$content_body = "Error. Vault not found in Banks.";
    		goto BODY;
    	}
		my $image = shift(@path); # image
		# show a list of image in the navigation
		$left_nav = "";
		foreach my $fvault (@{$$Options{'Runall'}}) {
			$left_nav .= '<li>Vault <a href="/browse/'.$fvault.'/">'.$fvault.'</a></li>';
			if($fvault eq $vault) {
				# show image in reverse chronological order
				foreach my $image (reverse sort glob("$bank/$vault/*")) {
					my @image_path = split("/", $image);
					if($image_path[-1] =~ m/^\d{4}/) {
						$left_nav .= 'Image <a href="/browse/'.$vault.'/'.$image_path[-1].'/">'.$image_path[-1].'</a>';
						$left_nav .= "<br />\n";
					}
				}
			}
		}
		if(!$image) {
			$content_title = "Browsing Vault $vault";
			$content_body = '<a href="/browse/">Up ..</a><br />';
			# show list of images and return
			# show image in reverse chronological order
			foreach my $image (reverse sort glob("$bank/$vault/*")) {
				my @image_path = split("/", $image);
				if($image_path[-1] =~ m/^\d{4}/) {
					$content_body .= 'Image <a href="/browse/'.$vault.'/'.$image_path[-1].'/">'.$image_path[-1].'</a>';
					$content_body .= ' - <a href="/log/'.$vault.'/'.$image_path[-1].'">Log</a> - <a href="/summary/'.$vault.'/'.$image_path[-1].'">Summary</a>';
					$content_body .= "<br />\n";
				}
			}
			goto BODY;
 		}
		$path = join("/",@path);
		#$path =~ s/[.][.]//g; # remove double dots
		#$path =~ s/(\/\s*\/)+/\//g; # remove repeated-slashes
		#print "New-Path: $path\n";
		# Get directory contents
		#my $fspath = $$Options{bank}[0]."/".$vault."/".$image."/tree/".$path;
		my $fspath = $bank."/".$vault."/".$image."/tree/".$path;
		@path = split("/",$path);
		#pop(@path);
		#print "Path1: @path\n";
		if(-d $fspath) {
			# show content of dir
			unshift(@path, $image);
			unshift(@path, $vault);
			$content_title = "Browsing ".join("/",@path)."/";
			pop(@path); # move one dir up for ..
			$content_body = '<a href="/browse/'.join("/",@path).'/">Up ..</a><br />';
			foreach my $file (glob("$fspath/*")) {
				my @file = split("/",$file);
				if(-f $file) {
					$content_body .= '<a href="'.url_encode($file[-1]).'"><img src="/page_white.png" border="0" /> '.$file[-1].' '.
					sprintf("%.2f",((stat($file))[7])/1024)
					.'kb </a><br />';
				} elsif(-d $file) {
					$content_body .= '<a href="'.url_encode($file[-1]).'/"><img src="/folder.png" border="0" /> '.$file[-1].'</a><br />';
				} else {
					$content_body .= '<a href="'.url_encode($file[-1]).'">??? '.$file[-1].'</a><br />';
				}
			}
		} elsif(-f $fspath) {
			#print "Sending File: $fspath\n";
			# send file
			$c->send_file_response($fspath);
			return 0;
		} else {
			#print "Error 404\n";
			# show error 404
			$content_body = "Error 404<br />\n";
		}
	} elsif($path =~ m#^/start_backup#) {
		# TODO start backup
		print "Would execute /etc/dirvish/dirvish-cronjob\n";
		$content_title = "Starting Backup";
		$content_body = "Starting Backup ...<br />";
	} elsif($path =~ m#^/stop_backup#) {
		# TODO stop backup
		print "Would execute kill `cat /var/run/dirvish.pid`\n";
		$content_title = "Stopping Backup";
		$content_body = "Stopping Backup ...<br />";
	} elsif($path =~ m#^/search#) {
		# TODO show search form
		$content_title = "Search";
		$content_body = '<form action="/search" method="POST">';
		$content_body .= '<input type="hidden" name="search" value="1" /><br />';
		$content_body .= 'Bank: <input type="text" name="query" /><br />';
		$content_body .= '<input type="submit" name="Submit" value="Submit" />';
		$content_body .= '</form>';
	} elsif($path =~ m#^/log#) {
		shift(@path); # (empty) root
		shift(@path); # action
		my $vault = shift(@path); # vault
		my $image = shift(@path); # image
		$content_title = "Log for $vault/$image";
		my $logpath = $$Options{bank}[0]."/".$vault."/".$image."/log";
		if(-f $logpath) {
			$content_body .= "<pre>\n";
			$content_body .= `cat $logpath`;
			$content_body .= "</pre>\n";
		}
	} elsif($path =~ m#^/summary#) {
		shift(@path); # (empty) root
		shift(@path); # action
		my $vault = shift(@path); # vault
		my $image = shift(@path); # image
		$content_title = "Summary for $vault/$image";
		my $logpath = $$Options{bank}[0]."/".$vault."/".$image."/summary";
		if(-f $logpath) {
			$content_body .= "<pre>\n";
			$content_body .= `cat $logpath`;
			$content_body .= "</pre>\n";
		}
	} elsif($path =~ m/\.png$/ && -e ".$path") {
		$c->send_file_response(".$path");
		return 0;
	}
	BODY:
	$body =~ s/_TOP_NAV_/$topnav/ if $topnav;
	$body =~ s/_LEFT_TITLE_/$left_title/ if $left_title;
	$body =~ s/_LEFT_NAV_/$left_nav/ if $left_nav;
	$body =~ s/_CONTENT_TITLE_/$content_title/ if $content_title;
	$body =~ s/_TITLE_/$content_title/ if $content_title;
	$body =~ s/_CONTENT_BODY_/$content_body/ if $content_body;
	# TODO replace 
	return res($body);
}

sub res {
	HTTP::Response->new(
		RC_OK, OK => [ 'Content-Type' => 'text/html' ], shift
	)
}
# http://support.internetconnection.net/CODE_LIBRARY/Perl_URL_Encode_and_Decode.shtml
sub url_encode {
	my $str = shift;
	$str =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	return $str;
}
# http://support.internetconnection.net/CODE_LIBRARY/Perl_URL_Encode_and_Decode.shtml
sub url_decode {
	my $str = shift;
	$str =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
	return $str;
}
# EOF