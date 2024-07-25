#!/usr/bin/perl

# un-preprocessed _changes-file as input

require "./vuln.pm";

# The amount of releases to include (0 == all)
my $lastfew = $ARGV[0];
if($lastfew < 1) {
    $lastfew = -1;
}
my $lastshow; # if $lastfew, this is the final release shown in the table

sub vernum {
    my ($ver)=@_;
    my @v = split('\.', $ver);
    return ($v[0] << 16) | ($v[1] << 8) | $v[2];
}

my @vname; # number + HTML links to each vulnerability page
print "<table>";
sub head {
    print "<tr class=\"tabletop\"><th>Version</th>";
    my $v=1;
    for(@vuln) {
        my ($id, $start, $stop, $desc, $cve, $announce, $report,
            $cwe, $award, $area, $cissue, $tool, $severity)=split('\|');

        if($lastshow && ($lastshow > vernum($stop))) {
            # not a match!
            next;
        }
        $id =~ s/ //;
        my $num = $#vuln - $v + 2;
        my $a=sprintf("<a style=\"color: white; text-decoration: none;\" href=\"$id\">%02</a>", $num);
        $vhref[$v-1]=$a;
        $vstart[$v-1]=$start;
        $vstop[$v-1]=$stop;
        $vurl[$v-1]= "$id";
        $vulndesc[$v-1]=$desc;
        $cve[$v-1]=$cve;
        $cwe[$v-1]=$cwe;
        $sev[$v-1]=$severity;
        printf("<th><a class=vuln title=\"$cve: $desc\" href=\"%s\">%02d</a></th>",
               $id, $num);
        $v++;
    }
    print "<th>Total</th>\n";
    print "</tr>\n";
    return $v-1;
}

sub sev2color {
    my ($severity) = @_;
    return 'green' if ($severity eq "low");
    return 'blue' if ($severity eq "medium");
    return 'red' if($severity eq "high");
    return "black";
}

sub single {
    my ($sum, $str, $date, $vernum, $vulns, $nextrel, $prevrel) = @_;

    # make a nice HTML list to include in the page
    my @v = split(/ /, $vulns);
    my $vulnhtml;
    my $vulnnum=scalar(@v);
    my $odd;
    my $vulnplural;

    if($vulnnum) {
        $vulnhtml = "<table><tr class=\"tabletop\"><th>Flaw</th><th>From version</th><th>To and including</th></tr>";

        for my $i (@v) {
            $vulnhtml .= sprintf("<tr class=\"%s\"><td><a href=\"%s\">%s</a></td><td><a href=\"vuln-%s.html\">%s</a></td><td><a href=\"vuln-%s.html\">%s</a></td></tr>\n",
                                 $odd&1?"even":"odd",
                                 $vurl[$i], $vulndesc[$i],
                                 $vstart[$i], $vstart[$i],
                                 $vstop[$i], $vstop[$i]);
            $odd++;
        }
        $vulnhtml .= "</table>";
    }
    else {
        # nothing known - yet
        $vulnhtml = "<p> <strong>There are no published security vulnerabilities for this version.</strong>";
    }

    my $n = "<p>  See vulnerability summary for ";

    if($prevrel) {
        $prev = 1;
        $n .= "<a href=\"vuln-$prevrel.html\">the previous release: $prevrel</a> ";
    }
    if($nextrel && ($nextrel ne $releases[-1])) {
        if($prev) {
            $n .= " or ";
        }
        $n .=  "<a href=\"vuln-$nextrel.html\">the subsequent release: $nextrel</a>";
    }

    my $anchor = $str;
    $anchor =~ s/\./_/g;

    if($vulnnum == 1) {
        $vulnplural = "";
    }
    else {
        $vulnplural = "s";
    }

    open(T, "<_singlevuln.templ");
    open(O, ">vuln-$str.gen");
    while(<T>) {
        $_ =~ s/%version/$str/g;
        $_ =~ s/%vulnerabilities/$vulnhtml/g;
        $_ =~ s/%date/$date/g;
        $_ =~ s/%vulnnum/$vulnnum/g;
        $_ =~ s/%vulnplural/$vulnplural/g;
        $_ =~ s/%anchor/$anchor/g;
        $_ =~ s/%nextprev/$n/g;
        print O $_;
    }
    close(T);
    close(O);

    # create a JSON bundle for this release
    open(O, ">vuln-$str.json");
    print O "[\n";
    my $c = 0;
    for my $i (@v) {
        open(S, "<$cve[$i].json");
        print O <S>;
        close(S);
        print O ",\n" if($c != $#v);
        $c++;
    }
    print O "\]\n";
    close(O);

}

my $l;

while(<STDIN>) {
    if($_ =~ /^SUBTITLE\(Fixed in ([0-9.]*) - (.*)\)/) {
        my $str=$1;
        my $date=$2;
        my $this = vernum($str);

        push @releases, $str;
        $reldate{$str}=$date;
        $vernum{$str}=$this;

        my $i=0;
        # Count how many versions each vuln applies to
        for(@vuln) {
            my ($id, $start, $stop)=split('\|');

            if(($this >= vernum($start)) &&
               ($this <= vernum($stop))) {
                # this version is vulnerable, count it per vuln
                $vercount[$i]++; # this applies
                $vervuln{$str} .= "$i ";
            }
            $i++;
        }
        if($#releases == $lastfew) {
            $lastshow = $this;
            last;
        }
    }
}

my $total = head();

$versions = scalar(@releases);

for my $str (@releases) {
    my $date = $reldate{$str};
    my $this = $vernum{$str};

    my @v;
    my $vnum;
    my $i;
    for(@vuln) {
        my ($id, $start, $stop)=split('\|');

        if(($this >= vernum($start)) &&
           ($this <= vernum($stop))) {
            # vulnerable
            $v[$i]=1; # this one
        }
        $i++;
    }
    my $anchor = $str;

    $anchor =~ s/\./_/g;

    printf("<tr class=\"%s\"><td><a href=\"vuln-$str.html\">$str</a></td>",
           $l&1?"even":"odd");
    my $col;
    my $sum;
    for my $i (0 .. $total-1 ) {
        if(!$v[$i]) {
            $col++;
        }
        else {
            if($col) {
                printf("<td colspan=\"%d\">&nbsp;</td>", $col);
                $col=0;
            }
            if(!$shown[$i]) {
                # output only once, but use rowspan for the height
                printf("<td valign=top style=\"background-color: %s;\" title=\"%s: %s (%s)\" rowspan=\"%d\" onclick=\"window.location.href='%s'\">&nbsp;</td>",
                       sev2color($sev[$i]),
                       $cve[$i], $vulndesc[$i], $sev[$i], $vercount[$i], $vurl[$i],);
                $shown[$i]=1;
            }
            $sum++;
        }
    }
    if($col) {
        printf("<td colspan=\"%d\">&nbsp;</td>", $col);
    }
    printf "<td>%d</td></tr>\n", $sum;

    single($sum, $str, $date, $this, $vervuln{$str},
           $releases[$l-1], $releases[$l+1]);

    ++$l;
}


for my $str (@releases) {
    $allhtml .= "vuln-$str.html ";
}

open(MAKE, ">vuln-make.gen");
print MAKE <<FOO
\#generated by vulntable.pl!
ROOT=..
SRCROOT=../cvssource
DOCROOT=\$(SRCROOT)/docs

include \$(ROOT)/mainparts.mk
include \$(ROOT)/setup.mk

MAINPARTS += adv-related-box.inc

all: ${allhtml}

clean:
	rm -f ${allhtml}

FOO
    ;
for my $str (@releases) {
    print MAKE "vuln-$str.html: vuln-$str.gen \$(MAINPARTS)\n";
    print MAKE "\t\$(ACTION)\n";
}
close(MAKE);

print "</table>\n";
