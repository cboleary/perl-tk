BEGIN { $|=1; $^W=1; }
use strict;

BEGIN {
    if (!eval q{
	use Test::More;
	1;
    }) {
	print "1..0 # skip: no Test::More module\n";
	exit;
    }
}

use Tk;
use Tk::Font;
use Getopt::Long;

plan tests => 34;

my $v;
GetOptions("v" => \$v)
    or die "usage: $0 [-v]";

my $mw = Tk::MainWindow->new;
$mw->geometry("+10+10");

##
## if there's only one (fixed) or no font family
## then something is wrong. Propably the envirionment
## and not perl/Tks fault.
##
{
    my @fam = ();
    eval { @fam = $mw->fontFamilies; };
    is($@, "", "fontFamilies");
    cmp_ok(@fam,">",1, "Num. of font families=".scalar @fam);
}
##
## Tk800.003 writes 'ont ...' in warning instead of 'font ...'
## fontActual expects one argument
##  opps,  looks like fault of ptksh
{
  eval { $mw->fontActual; };
  like($@, qr/^wrong # args: should be "font/,
       "fontActual without font error");
}
##
## Stephen O. Lidie reported that Tk800.003
## fontMeasure() and fontMeasure(fontname) gives
## SEGV on linux and AIX.
##
{
  my $fontname = ($^O eq 'MSWin32') ? 'ansifixed': 'fixed';
  eval { $mw->fontMeasure; };
  isnt($@, "", "fontMeasure documented to require two args, not zero");
  eval { $mw->fontMeasure($fontname); };
  isnt($@, "", "fontMeasure documented to require two args, not one");
  my $num = undef;
  eval { $num = $mw->fontMeasure($fontname, 'Hi'); };
  is($@, "", "fontMeasure works with fixed font and a string");
  ok(defined $num);
  cmp_ok($num, ">=", 2, "fontMeasure value is large enough");
  my $l = $mw->Label(-font => $fontname);
  my $name;
  eval { $name = $l->cget('-font') };
  is("$name", $fontname, "cget(-font) returns same fontname");
}

my @fam = $mw->fontFamilies;
if ($v)
 {
  diag "Font families:";
  foreach my $fam (@fam)
   {
    diag "* $fam";
   }
 }

SKIP:
 {
  skip("Times not available", 4)
      if !grep { /^times$/i } @fam;

  $mw->optionAdd('*Listbox.font','Times -12 bold');
  my $lb = $mw->Listbox()->pack;
  $lb->insert(end => '0',"\xff","\x{20ac}","\x{0289}");
  $lb->update;
  my $lf = $lb->cget('-font');
  diag "Font attributes: $$lf:" . join(',',$mw->fontActual($lf))
      if $v;
  my %expect = (-family => 'Times',
		-size   => -12, -weight => 'bold',
		-slant  => 'roman');
  foreach my $key (sort keys %expect)
   {
    my $val = $mw->fontActual($lf,$key);
    like($val, qr{\Q$expect{$key}}i, "Value of $key from fontActual");
   }

  my @subfonts = $mw->fontSubfonts($lf);
  if ($v)
   {
    diag "Subfonts of $$lf:";
    foreach my $sf (@subfonts)
     {
      diag '* ' . join(',',@$sf);
     }
   }
 }

# This is really only needed for checking the -ascent and -descent values
# if Perl/Tk was built with XFT=1 and by requesting helvetica really
# the X11 helvetica was returned.
SKIP: {
 skip("Test only work on X11", 10)
     if $Tk::platform ne 'unix';

 my $l = $mw->Label(-font => '-*-Helvetica-Bold-R-Normal--*-180-*-*-*-*-*-*');
 my $f = $l->cget(-font);
 my %fa = ($mw->fontActual($f), $mw->fontMetrics($f));

 skip("Helvetica requested, but got $fa{-family}", 10)
     if lc $fa{-family} ne 'helvetica';

 my %expected = (
		 "-weight"     => "bold",
		 "-underline"  => 0,
		 "-family"     => "helvetica",
		 "-slant"      => "roman",
		 "-size"       => -18,
		 "-overstrike" => 0,
		 "-ascent"     => 16,
		 "-descent"    => 5,
		 "-linespace"  => 21,
		 "-fixed"      => 0,
		);
 while(my($key,$val) = each %expected)
  {
   is(lc $fa{$key}, $val, "Expected $key value");
  }
 $l->destroy;
}

{
 # This caused core dumps with Xft version of Perl/Tk
 my $l = $mw->Label(-font => '-*-*-bold-r-*--12-*-*-*-*-*-*-*');
 $l->destroy;
 pass("Core dump check (especially for XFT)");
}

{
 # This caused core dumps with Perl/Tk 804.027
 eval { $mw->fontMeasure(undef, -ascent)};
 like($@, qr{Cannot use undef as font object},
      "Core dump check with undef font object");

 eval { $mw->fontConfigure(undef) };
 like($@, qr{Cannot use undef as font object});

 eval { $mw->fontActual(undef) };
 like($@, qr{Cannot use undef as font object});
}

{
 # This caused core dumps with Perl/Tk 804.027
 my $l = $mw->Label(-font => "helvetica 10");
 my $f = $l->cget(-font);
 eval { $l->configure(-font => undef) };
 like($@, qr{\QCannot use undef value for object of type 'font'},
      "Core dump check with undef font in configure");
 is($l->cget(-font), $f, "Font stays unchanged");
 $l->destroy;

 eval { $mw->Label(-font => undef) };
 like($@, qr{\QCannot use undef value for object of type 'font'},
      "Core dump check with undef font in initial setup (label)");

 require Tk::TextList; # TextList seems to be special
 eval { $mw->TextList(-font => undef) };
 like($@, qr{\QCannot use undef value for object of type 'font'},
      "Core dump check with undef font in initial setup (textlist)");
 # FIXME XXX
 # The above failure causes a font to be left in the cache. The message:
 # Font -*-helvetica-medium-r-normal--14-*-*-*-*-iso8859-1 still in cache.
}

{
 my $l = $mw->Label;
 my $f = $l->cget(-font);
 isa_ok($f, 'Tk::Font');
 my $ascent = $f->measure(-ascent);
 ok(defined $ascent, "Got ascent from measure");
 eval { $f->actual(undef,undef) };
 like($@, qr{\Qwrong # args: should be "font actual font},
      "Does not get error about undef font object");
}

__END__
