#!/usr/bin/perl
# dirvish-locate
# 1.3.X series
# Copyright 2005 by the dirvish project
# http://www.dirvish.org
#
# Last Revision   : $Rev: 660 $
# Revision date   : $Date: 2009-02-17 18:43:32 +0100 (Di, 17 Feb 2009) $
# Last Changed by : $Author: tex $
# Stored as       : $HeadURL: https://secure.id-schulz.info/svn/tex/priv/dirvish_1_3_1/dirvish-locate.pl $
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
#----------------------------------------------------------------------------
# Revision information
#----------------------------------------------------------------------------
my %CodeID = (
    Rev    => '$Rev: 660 $'     ,
    Date   => '$Date: 2009-02-17 18:43:32 +0100 (Di, 17 Feb 2009) $'    ,
    Author => '$Author: tex $'  ,
    URL    => '$HeadURL: https://secure.id-schulz.info/svn/tex/priv/dirvish_1_3_1/dirvish-locate.pl $' ,
);

$VERSION =   $CodeID{URL};
$VERSION =~  s#^.*dirvish_##;  # strip off the front
$VERSION =~  s#\/.*##;         # strip off the rear after the last /
$VERSION =~  s#[_-]#.#g;       # _ or - to "."

#----------------------------------------------------------------------------
# Modules and includes
#----------------------------------------------------------------------------
use strict;
use warnings;

use Time::ParseDate;
use POSIX qw(strftime);
use Getopt::Long;
use Dirvish;

use File::Spec::Functions;

#----------------------------------------------------------------------------
# SIG Handler
#----------------------------------------------------------------------------
$SIG{TERM} = \&sigterm; # handles "kill <PID>"
$SIG{INT} = \&sigterm; # handles Ctrl+C or "kill -2 <PID>"

#----------------------------------------------------------------------------
# Initialisation
#----------------------------------------------------------------------------
my $KILLCOUNT = 1000;
my $MAXCOUNT = 100;

my $Options = reset_options( \&usage, @ARGV);	# initialize the %$Options hash
load_master_config('f', $Options);				# load master config into $Options

GetOptions($Options, qw(
    version
    help|?
    )) or &usage();

my $Vault = shift;
my $Branch = undef;
$Vault =~ /:/ and ($Vault, $Branch) = split(/:/, $Vault);
my $Pattern = shift;

$Vault && length($Pattern) or &usage();
# prepend dot if asterisk or question mark is
# the first character. Make rsync-like patterns like *.xml work
$Pattern = ".".$Pattern if($Pattern =~ m/^(\*|\?)/);

my $fullpattern = $Pattern;
my $partpattern = undef;
$fullpattern =~ /\$$/ or $fullpattern .= '[^/]*$';
($partpattern = $fullpattern) =~ s/^\^//;

my $bank = undef;
for $b (@{$$Options{bank}})
{
    -d catdir($b,$Vault) and $bank = $b;
}
$bank or seppuku 220, "No such vault: $Vault";

opendir VAULT, catdir($bank,$Vault) or seppuku 221, "cannot open vault: $Vault";
my @invault = readdir(VAULT);
closedir VAULT;

my @images = ();
for my $image (@invault)
{
    $image eq 'dirvish' and next;
    my $imdir = catdir($bank,$Vault,$image);
    -f catfile($imdir,"summary") or next;
    (-l $imdir && $imdir =~ /current/) and next; # skip current-symlink
    my $conf = loadconfig('R', catfile($imdir,"summary"), $Options) or next;
    $$conf{Status} eq 'success' || $$conf{Status} =~ /^warn/
        or next;
    $$conf{'Backup-complete'} or next;
    $Branch && $$conf{branch} ne $Branch and next;
	
    unshift @images, {
        imdir   => $imdir,
        image   => $$conf{Image},
        branch  => $$conf{branch},
        created => $$conf{'Backup-complete'},
    }
}

my $imagecount = 0;
my $pathcount = 0;
my $path = undef;
my %match = ();
for my $image (sort(imsort_locate @images))
{
    my $imdir = $$image{imdir};

    my $index = undef;
    -f catfile($imdir,"index.bz2") and $index = "bzip2 -d -c ".catfile($imdir,"index.bz2")."|";
    -f catfile($imdir,"index.gz") and $index = "gzip -d -c ".catfile($imdir,"index.gz")."|";
    -f catfile($imdir,"index") and $index = "<".catfile($imdir,"index");
    $index or next;

    ++$imagecount;

	# can't use three-fold open here, see above
    open(INDEX, $index) or next;
    while (<INDEX>)
    {
        chomp;

        m($partpattern) or next;
		# this parse operation is too slow.  It might be faster as a
		# split with trimmed leading whitespace and remerged modtime
        my $f = { image => $image };
        (
             $$f{inode},
            $$f{blocks},
            $$f{perms},
            $$f{links},
            $$f{owner},
            $$f{group},
            $$f{bytes},
            $$f{mtime},
            $path
        ) = m<^
            \s*(\S+)        # inode
            \s+(\S+)        # block count
            \s+(\S+)        # perms
            \s+(\S+)        # link count
            \s+(\S+)        # owner
            \s+(\S+)        # group
            \s+(\S+)        # byte count
            \s+(\S+\s+\S+\s+\S+)    # date
            \s+(\S.*)        # path
        $>x;
        $$f{perms} =~ /^[dl]/ and next;
        $path =~ m($fullpattern) or next;

        exists($match{$path}) or ++$pathcount;
        push @{$match{$path}}, $f;
    }
    if ($pathcount >= $KILLCOUNT)
    {
        print "dirvish-locate: too many paths match pattern, interrupting search\n";
        last;
    }
}

printf "%d matches in %d images\n", $pathcount, $imagecount;

$pathcount >= $MAXCOUNT
    and printf "Pattern '%s' too vague, listing paths only.\n", $Pattern;

my $last = undef;
my $linesize = 0;
for my $path (sort(keys(%match)))
{
    $last = undef;
    print $path;

    if ($pathcount >= $MAXCOUNT)
    {
        print "\n";
               next;
    }

    for my $hit (@{$match{$path}})
    {
        my $inode = $$hit{inode};
        my $mtime = $$hit{mtime};
        my $image = $$hit{image}{image};
        if (defined($last) && $inode ne $last)
        {
            $linesize = 5 + length($mtime) + length($image);
            printf "\n    %s %s", $mtime, $image;
        } else {
            $linesize += length($image) + 2;
            if ($linesize > 78)
            {
                $linesize = 5 + length($mtime) + length($image);
                print "\n",
                    " " x (5 + length($mtime)),
                    $image;
            } else {
                printf ", %s", $$hit{image}{image};
            }
        }
        $last = $inode;
    }
    print "\n\n";
}

exit 0;
#----------------------------------------------------------------------------
# Subs
#----------------------------------------------------------------------------
# Sort images
sub imsort_locate {
	## WARNING:  don't mess with the sort order, it is needed so that if
	## WARNING:  all images are expired the newest will be retained.
	$$a{branch} cmp $$b{branch}
	  || $$a{created} cmp $$b{created};
}
sub usage
{
    my $message = shift(@_);

    length($message) and print STDERR $message, "\n\n";

    print STDERR <<EOUSAGE;
USAGE
	dirvish-locate vault[:branch] pattern
	
	Pattern can be any PCRE.
	
EOUSAGE
	exit 255;
}
# Handle SIGTERM (SIG-15)
sub sigterm
{
	print STDERR "Received SIGTERM. Aborting running backup ...";
	# kill childs - kill(TERM, -$$):
	use POSIX;
	my $cnt = kill(SIGTERM, -$$);
	no POSIX;
	print STDERR "Signaled $cnt processes in current processgroup";
	# quit
	exit;
}
#----------------------------------------------------------------------------
# EOF
#----------------------------------------------------------------------------