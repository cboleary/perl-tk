# Copyright (c) 1995-1999 Nick Ing-Simmons. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
package Tk::Derived;
require Tk::Widget;
require Tk::Configure;
use strict;
use Carp;

use vars qw($VERSION);
$VERSION = '3.027'; # $Id: //depot/Tk8/Tk/Derived.pm#27$

$Tk::Derived::Debug = 0;

my $ENHANCED_CONFIGSPECS = 0; # disable for now

use Tk qw(NORMAL_BG BLACK);

sub Subwidget
{
 my $cw = shift;
 my @result = ();
 if (exists $cw->{SubWidget})
  {
   if (@_)
    {
     my $name;
     foreach $name (@_)
      {
       push(@result,$cw->{SubWidget}{$name}) if (exists $cw->{SubWidget}{$name});
      }
    }
   else
    {
     @result = values %{$cw->{SubWidget}};
    }
  }
 return (wantarray) ? @result : $result[0];
}

sub _makelist
{
 my $widget = shift;
 my (@specs) = (ref $widget && ref $widget eq 'ARRAY') ? (@$widget) : ($widget);
 return @specs;
}

sub Subconfigure
{
 # This finds the widget or widgets to to which to apply a particular
 # configure option
 my ($cw,$opt) = @_;
 my $config = $cw->ConfigSpecs;
 my $widget;
 my @subwidget = ();
 my @arg = ();
 if (defined $opt)
  {
   $widget = $config->{$opt};
   unless (defined $widget)
    {
     $widget = ($opt =~ /^-(.*)$/) ? $config->{$1} : $config->{-$opt};
    }
   # Handle alias entries
   if (defined($widget) && !ref($widget))
    {
     $opt    = $widget;
     $widget = $config->{$widget};
    }
   push(@arg,$opt) unless ($opt eq 'DEFAULT');
  }
 $widget = $config->{DEFAULT} unless (defined $widget);
 if (defined $widget)
  {
   $cw->BackTrace("Invalid ConfigSpecs $widget") unless (ref($widget) && (ref $widget eq 'ARRAY'));
   $widget = $widget->[0];
  }
 else
  {
   $widget = 'SELF';
  }
 foreach $widget (_makelist($widget))
  {
   $widget = 'SELF' if (ref($widget) && $widget == $cw);
   if (ref $widget)
    {
     my $ref = ref $widget;
     if ($ref eq 'ARRAY')
      {
       $widget = Tk::Configure->new(@$widget);
       push(@subwidget,$widget)
      }
     elsif ($ref eq 'HASH')
      {
       my $key;
       foreach $key (%$widget)
        {
         my $sw;
         foreach $sw (_makelist($widget->{$key}))
          {
           push(@subwidget,Tk::Configure->new($sw,$key));
          }
        }
      }
     else
      {
       push(@subwidget,$widget)
      }
    }
   elsif ($widget eq 'ADVERTISED')
    {
     push(@subwidget,$cw->Subwidget)
    }
   elsif ($widget eq 'DESCENDANTS')
    {
     push(@subwidget,$cw->Descendants)
    }
   elsif ($widget eq 'CHILDREN')
    {
     push(@subwidget,$cw->children)
    }
   elsif ($widget eq 'METHOD')
    {
     my ($method) = ($opt =~ /^-?(.*)$/);
     push(@subwidget,Tk::Configure->new($method,$method,$cw))
    }
   elsif ($widget eq 'SETMETHOD')
    {
     my ($method) = ($opt =~ /^-?(.*)$/);
     push(@subwidget,Tk::Configure->new($method,'_cget',$cw,@arg))
    }
   elsif ($widget eq 'SELF')
    {
     push(@subwidget,Tk::Configure->new('Tk::configure', 'Tk::cget', $cw,@arg))
    }
   elsif ($widget eq 'PASSIVE')
    {
     push(@subwidget,Tk::Configure->new('_configure','_cget',$cw,@arg))
    }
   elsif ($widget eq 'CALLBACK')
    {
     push(@subwidget,Tk::Configure->new('_callback','_cget',$cw,@arg))
    }
   else
    {
     push(@subwidget,$cw->Subwidget($widget));
    }
  }
 $cw->BackTrace("No delegate subwidget '$widget' for $opt") unless (@subwidget);
 return (wantarray) ? @subwidget : $subwidget[0];
}

sub _cget
{
 my ($cw,$opt) = @_;
 $cw->BackTrace('Wrong number of args to cget') unless (@_ == 2);
 return $cw->{Configure}{$opt}
}

sub _configure
{
 my ($cw,$opt,$val) = @_;
 $cw->BackTrace('Wrong number of args to configure') unless (@_ == 3);
 $cw->{Configure}{$opt} = $val;
}

sub _callback
{
 my ($cw,$opt,$val) = @_;
 $cw->BackTrace('Wrong number of args to configure') unless (@_ == 3);
 $val = Tk::Callback->new($val) if defined $val;
 $cw->{Configure}{$opt} = $val;
}

sub cget
{my ($cw,$opt) = @_;
 my @result;
 local $SIG{'__DIE__'};
 foreach my $sw ($cw->Subconfigure($opt))
  {
   eval {  @result = $sw->cget($opt) };
   last unless @_;
  }
 return (wantarray) ? @result : $result[0];
}

sub Configured
{
 # Called whenever a derived widget is re-configured
 my ($cw,$args,$changed) = @_;
 if (@_ > 1)
  {
   $cw->DoWhenIdle(['ConfigChanged',$cw,$changed]) if (%$changed);
  }
 return exists $cw->{'Configure'};
}

sub configure
{
 # The default composite widget configuration method uses hash stored
 # in the widget's hash to map configuration options
 # onto subwidgets.
 #
 my @results = ();
 my $cw = shift;
 if (@_ <= 1)
  {
   # Enquiry cases
   my $spec = $cw->ConfigSpecs;
   if (@_)
    {
     # Return info on the nominated option
     my $opt  = $_[0];
     my $info = $spec->{$opt};
     unless (defined $info)
      {
       $info = ($opt =~ /^-(.*)$/) ? $spec->{$1} : $spec->{-$opt};
      }
     if (defined $info)
      {
       if (ref $info)
        {
         # If the default slot is undef then ask subwidgets in turn
         # for their default value until one accepts it.
         if ($ENHANCED_CONFIGSPECS && !defined($info->[3]))
          {local $SIG{'__DIE__'};
           my @def;
           foreach my $sw ($cw->Subconfigure($opt))
            {
             eval { @def = $sw->configure($opt) };
             last unless $@;
            }
           $info->[3] = $def[3];
           $info->[1] = $def[1] unless defined $info->[1];
           $info->[2] = $def[2] unless defined $info->[2];
          }
         push(@results,$opt,$info->[1],$info->[2],$info->[3],$cw->cget($opt));
        }
       else
        {
         # Real (core) Tk widgets return db name rather than option name
         # for aliases so recurse to get that ...
         my @real = $cw->configure($info);
         push(@results,$opt,$real[1]);
        }
      }
     else
      {
       push(@results,$cw->Subconfigure($opt)->configure($opt));
      }
    }
   else
    {
     my $opt;
     my %results;
     if (exists $spec->{'DEFAULT'})
      {
       foreach $opt ($cw->Subconfigure('DEFAULT')->configure)
        {
         $results{$opt->[0]} = $opt;
        }
      }
     foreach $opt (keys %$spec)
      {
       $results{$opt} = [$cw->configure($opt)] if ($opt ne 'DEFAULT');
      }
     foreach $opt (sort keys %results)
      {
       push(@results,$results{$opt});
      }
    }
  }
 else
  {
   my (%args) = @_;
   my %changed = ();
   my ($opt,$val);
   $cw->{Configure} = {} unless exists $cw->{Configure};
   while (($opt,$val) = each %args)
    {
     my $var = \$cw->{Configure}{$opt};
     my $old = $$var;
     my $subwidget;
     $$var = $val;
     my $accepted = 0;
     my $error = "No widget handles $opt";
     foreach my $subwidget ($cw->Subconfigure($opt))
      {
       next unless (defined $subwidget);
       eval {local $SIG{'__DIE__'};  $subwidget->configure($opt => $val) };
       if ($@)
        {
         my $val2 = (defined $val) ? $val : 'undef';
         $error = "Can't set $opt to `$val2' for $cw: " . $@;
         undef $@;
        }
       else
        {
         $accepted = 1;
        }
      }
     $cw->BackTrace($error) unless ($accepted);
     $val = $$var;
     $changed{$opt} = $val if (!defined $old || !defined $val || "$old" ne "$val");
    }
   $cw->Configured(\%args,\%changed);
  }
 return (wantarray) ? @results : $results[0];
}

sub ConfigDefault
{
 my ($cw,$args) = @_;

 $cw->BackTrace('Bad args') unless (defined $args && ref $args eq 'HASH');

 my $specs = $cw->ConfigSpecs;
 # Should we enforce a Delagates(DEFAULT => )  as well ?
 $specs->{'DEFAULT'} = ['SELF'] unless (exists $specs->{'DEFAULT'});

 #
 # This is a pain with Text or Entry as core widget, they don't
 # inherit SELF's cursor. So comment it out for Tk402.001
 #
 # $specs->{'-cursor'} = ['SELF',undef,undef,undef] unless (exists $specs->{'-cursor'});

 # Now some hacks that cause colours to propogate down a composite widget
 # tree - really needs more thought, other options adding such as active
 # colours too and maybe fonts

 my $children = scalar($cw->children);

 unless (exists($specs->{'-background'}))
  {
   my (@bg) = ('SELF');
   push(@bg,'CHILDREN') if $children;
   $specs->{'-background'} = [\@bg,'background','Background',NORMAL_BG];
  }
 unless (exists($specs->{'-foreground'}))
  {
   my (@fg) = ('PASSIVE');
   unshift(@fg,'CHILDREN') if $children;
   $specs->{'-foreground'} = [\@fg,'foreground','Foreground',BLACK];
  }
 $cw->ConfigAlias(-fg => '-foreground', -bg => '-background');

 # Pre-scan args for aliases - this avoids defaulting
 # options specified via alias
 my $opt;
 foreach $opt (keys %$args)
  {
   my $info = $specs->{$opt};
   if (defined($info) && !ref($info))
    {
     $args->{$info} = delete $args->{$opt};
    }
  }

 # Now walk %$specs supplying defaults for all the options
 # which have a defined default value, potentially looking up .Xdefaults database
 # options for the name/class of the 'frame'

 foreach $opt (keys %$specs)
  {
   if ($opt ne 'DEFAULT')
    {
     unless (exists $args->{$opt})
      {
       my $info = $specs->{$opt};
       if (ref $info)
        {
         # Not an alias
         if ($ENHANCED_CONFIGSPECS && !defined $info->[3])
          {
           # configure inquire to fill in default slot from subwidget
           $cw->configure($opt);
          }
         if (defined $info->[3])
          {
           if (defined $info->[1] && defined $info->[2])
            {
             # Should we do this on the Subconfigure widget instead?
             # to match *Entry.Background
             my $db = $cw->optionGet($info->[1],$info->[2]);
             $info->[3] = $db if (defined $db);
            }
           $args->{$opt} = $info->[3];
          }
        }
      }
    }
  }
}


sub ConfigSpecs
{
 my $cw = shift;
 if (exists $cw->{'ConfigSpecs'})
  {
   my $specs = $cw->{'ConfigSpecs'};
   while (@_)
    {
     my $key = shift;
     my $val = shift;
     $specs->{$key} = $val;
    }
  }
 else
  {
   $cw->{'ConfigSpecs'} = { @_ };
  }
 return $cw->{'ConfigSpecs'};
}

sub ConfigAlias
{
 my $cw = shift;
 my $specs = $cw->ConfigSpecs;
 while (@_ >= 2)
  {
   my $opt  = shift;
   my $main = shift;
   if (exists($specs->{$opt}) && ref($specs->{$opt}))
    {
     $specs->{$main} = $opt unless (exists $specs->{$main});
    }
   elsif (exists($specs->{$main}) && ref($specs->{$main}))
    {
     $specs->{$opt}  = $main unless (exists $specs->{$opt});
    }
   else
    {
     $cw->BackTrace("Neither $opt nor $main exist");
    }
  }
 $cw->BackTrace('Odd number of args to ConfigAlias') if (@_);
}

sub Delegate
{
 my ($cw,$method,@args) = @_;
 my $widget = $cw->DelegateFor($method);
 $method = "Tk::$method" if ($widget == $cw);
 my @result;
 if (wantarray)
  {
   @result   = $widget->$method(@args);
  }
 else
  {
   $result[0] = $widget->$method(@args);
  }
 return (wantarray) ? @result : $result[0];
}

sub InitObject
{
 my ($cw,$args) = @_;
 $cw->Populate($args);
 $cw->ConfigDefault($args);
}

sub ConfigChanged
{
 my ($cw,$args) = @_;
}

sub Advertise
{
 my ($cw,$name,$widget)  = @_;
 confess 'No name' unless (defined $name);
 croak 'No widget' unless (defined $widget);
 $cw->{SubWidget} = {} unless (exists $cw->{SubWidget});
 $cw->{SubWidget}{$name} = $widget;              # advertise it
 return $widget;
}

sub Component
{
 my ($cw,$kind,$name,%args) = @_;
 $args{'Name'} = "\l$name" if (defined $name && !exists $args{'Name'});
 # my $pack = delete $args{'-pack'};
 my $delegate = delete $args{'-delegate'};
 my $w = $cw->$kind(%args);            # Create it
 # $w->pack(@$pack) if (defined $pack);
 $cw->Advertise($name,$w) if (defined $name);
 $cw->Delegates(map(($_ => $w),@$delegate)) if (defined $delegate);
 return $w;                            # and return it
}

1;
__END__


