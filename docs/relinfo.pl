#!/usr/bin/perl

my $raw; # raw output. no html

if($ARGV[0] eq "--raw") {
    $raw=1;
}

sub vernum {
    my ($ver)=@_;
    my @v = split('\.', $ver);
    return ($v[0] << 16) | ($v[1] << 8) | $v[2];
}

print "<table>" if(!$raw);
sub head {
    if($raw) {
        return;
    }
    print "<tr class=\"tabletop\"><th rowspan=\"2\">#</th><th rowspan=\"2\">Version</th>";
    printf("<th rowspan=\"2\">Date</th><th rowspan=\"2\">Since %s</th><th colspan=\"3\">Delta</th><th colspan=\"4\">Accumulated</th></tr>\n", $releases[0]);
    print "<tr class=\"tabletop\"><th>Days</th><th>Bugfixes</th><th>Changes</th><th>Days</th><th>Bugfixes</th><th>Changes</th><th>Vulns</th></tr>\n";
}

my $l;

# made by vulntable.pl
open(A, "<allvulns.gen");
my %vulns;
while(<A>) {
    if($_ =~ /^([^:]*): (\d+)/) {
        $vulns{$1} = $2;
    }
}
close(A);

my $str;
while(<STDIN>) {
    # each release starts with this
    if($_ =~ /^SUBTITLE\(Fixed in ([0-9.]*) - (.*)\)/) {
        $str=$1;
        my $date=$2;

        push @releases, $1;
        $reldate{$1}=$2;
        $bugfixes{$str}=0;
        $changes{$str}=0;
    }
    elsif($str && ($_ =~ /^ *BGF/)) {
        # bugfix for version $str
        $bugfixes{$str}++;
    }
    elsif($str && ($_ =~ /^ *CHG/)) {
        # change for version $str
        $changes{$str}++;
    }
}

my $numreleases = $#releases + 1;

# do a loop to fix dates
for my $str (@releases) {
    my $date = $reldate{$str};
    my $datesecs=`date -d "$date" +%s`;
    my $dateymd=`date -d "$date" +%F`;
    chomp $dateymd;
    my $daysbetween;
    my $deltadays=0;

    if($prevsecs) {
        # number of seconds between two releases!
        # (plus one hour to make DST switches not reduce days)
        my $reltime = $prevsecs - $datesecs + 3600;

        # convert to days
        $daysbetween = int($reltime/(3600*24));

        # deltadays is the number of days between two releases
        $deltadays = abs($prevdays - $daysbetween);

        if($daysbetween < 100) {
            $age = "$daysbetween days";
        }
        elsif($daysbetween < 400) {
            $age = sprintf("%d months", int($daysbetween/30));
        }
        else {
            my $mon = int(($daysbetween%365)/30);
            $age = sprintf("%.1f years", $daysbetween/365);
        }
        $prevdays = $daysbetween; # store number of days between this and the most
                                  # recent
    }
    else {
        # store the first date
        $prevsecs = $datesecs;
        $prevdays = 0;
        $age=$raw?"0":"&ndash;";
    }
    $since{$str}=$age;
    $delta{$str}=$deltadays;
    $ymd{$str}=$dateymd;

    # the newer release
    $newer{$str}=$prevstr;

    if($prevstr) {
        # there is a newer version, make a later mapping for it!
        $later{$prevstr} = $str;
    }

    $prevstr=$str;
}


head();

my $totalbugs;
my $totalchanges;
for my $str (@releases) {
    my $this = vernum($str);
    my $date = $reldate{$str};
    my $dateymd = $ymd{$str};

    my @v;
    my $vnum;
    my $i;
    for(@vuln) {
        my ($id, $start, $stop)=split('\|');

        #print "CHECK $start <= $this <= $stop\n";

        if(($this >= vernum($start)) &&
           ($this <= vernum($stop))) {
            # vulnerable
            $v[$i]=1; # this one
        }
        $i++;
    }
    if($raw) {
        printf "%d;$str;", $index;
    }
    else {
        printf("<tr class=\"%s\"><td>%d</td><td><a href=\"/ch/$str.html\">$str</a></td>",
               $l&1?"even":"odd",
               $numreleases - $index);
    }
    $index++;

    if($raw) {
        printf "%d;", $vulns{$str};
    }

    if($date =~ /([A-Za-z]+) (\d+) (\d\d\d\d)/) {
        if(!$raw) {
            # a long month name, use the shorter version
            $date = substr($1, 0, 3)."&nbsp;$2&nbsp;$3";
        }
    }
    $totalchanges += $changes{$str};
    $totalbugs += $bugfixes{$str};

    my $age = $since{$str};

    # figure out the number of days between the previous release and this
    my $deltadays = $delta{$later{$str}};
    $totaldays += $deltadays;

    if($raw) {
        printf("$dateymd;$age;%d;$totaldays;%d;%d;%d;%d;\n",
               $deltadays,
               $bugfixes{$str}, $totalbugs,
               $changes{$str}, $totalchanges);
    }
    else {
        if(! -f "vuln-$str.html") {
            $v = "0";
        }
        else {
            $v = sprintf("<a href=\"vuln-$str.html\">%d</a>", $vulns{$str});
        }
        printf("<td>$date</td><td>$age</td><td>$deltadays</td><td>%d</td><td>%d</td><td>$totaldays</td><td>%d</td><td>%d</td><td>$v</td></tr>\n",
               $bugfixes{$str}, $changes{$str},
               $totalbugs, $totalchanges);
    }

    ++$l;
}

print "</table>\n" if(!$raw);
