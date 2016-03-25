###########
# Utility #
###########

package Roguelike::Utility;

use strict;
use warnings;
use Roguelike::Game;

use Data::Dumper;

use Exporter ();
our @ISA = ("Exporter");
our @EXPORT = do {
  no strict "refs";
  grep defined &$_, keys %{ __PACKAGE__ . "::" };
};

sub say {
  return if $Game->{Silence};
  my $msg = shift;
  # Blasted vim editing style.
  $msg =~ s/\n/ /g; # Right?
  $msg =~ s/\s+/ /g;
  push @{ $Game->{Messages} }, $msg;
  return 1;
}

sub complain {
  say "[DEBUG] " . shift;
}

sub debug {
  $Data::Dumper::Deparse = 1;
  $Data::Dumper::Maxdepth = 3;
  print STDERR Dumper(@_);
}

sub saydump {
  # Just bypass the normal facilities for adding messages.
  push @{ $Game->{Messages} }, Dumper(@_);
}

sub random {
  if (scalar @_ > 2) {
    debug "WARNING: random() called with >2 arguments, assuming chooserand().";
    chooserand(@_);
  }
  my $rand;
  # First try the queue.
  if (@{ $Game->{Random}{Queued} }) {
    $rand = shift @{ $Game->{Random}{Queued} };
  } else {
    # Add support for interactively prompting for a random number
    if (scalar @_ == 1) {
      my $max = shift;
      $rand = int rand($max);
      $rand = $max if $rand > $max;
    } elsif (scalar @_ == 2) {
      my ($min, $max) = @_;
      if ($min == $max) {
        $rand = $min;
      } else {
        ($min, $max) = ($max, $min) if $min > $max;
        $rand = $min + int rand(1 + $max - $min);
      }
    }
  }
  # Store in used.
  push @{ $Game->{Random}{Used} }, $rand;
  return $rand;
}

sub chooserand {
  return $_[ random(0, $#_) ];
}

sub percent {
  return 1 if random(100) <= shift;
}

sub signal {
  my $when = shift;
  my $subj = shift;
  my $verb = shift;
  my $arg1 = shift;
  my $arg2 = shift;
  # The only things we have to screw with are arg1 and arg2.
  if ($verb ne "is") {
    $arg1 = $Game->{Templates}{Obj} unless ref $arg1;
    $arg2 = $Game->{Templates}{Obj} unless ref $arg2;
  } else {
    return -1 unless defined $arg1;  # Before monkey is ? 5... I THINK NOT!
    $arg2 = 0 unless defined $arg2;
  }
  if ($verb eq "is") {
    # It's easier to duplicate code than make the normal event dispatcher work
    # with non-object arguments.
    my (@react1, @react2, @react3);
    foreach my $actor ($subj, $subj->bases) {
      next unless $actor->{$when}{$verb}{$arg1};
      # arg2 can either be itself or 0.
      my @list = ($arg2);
      push @list, 0 unless $arg2 == 0;
      foreach (@list) {
        next unless $actor->{$when}{$verb}{$arg1}{$_};
        my $reactions = $actor->{$when}{$verb}{$arg1}{$_};
        # Add the reactions to the master list.
        push @react1, @{ $reactions->[0] }; # -1
        push @react2, @{ $reactions->[1] }; # normal
        unshift @react3, @{ $reactions->[2] };  # 1
      }
    }
    # Now there are three lists of reactions. Execute them all!
    my $code = 1;
    foreach (@react1, @react2, @react3) {
      # For now, those fancy scope conditions won't work.
      $code = $_->{Reaction}->($subj, $verb, $arg1, $arg2); # Beauty.
      last if $code == -1;
    }
    return $code; # Yay.
  } else {
    return event($when, $subj, $verb, $arg1, $arg2);
  }
}

sub event {
  # No extra data, yet, sorry.
  my ($when, $subj, $verb, $arg1, $arg2) = @_;
  # Assume we have all arguments and that they're objects, not data.
  my (@react1, @react2, @react3);
  foreach my $actor ($subj, $subj->bases) {
    next unless $actor->{$when}{$verb};
    # Now arg1...
    foreach my $obj1 ($arg1, $arg1->bases) {
      my $id1 = $obj1->{ID};
      next unless $actor->{$when}{$verb}{$id1};
      # And arg2, finally...
      foreach my $obj2 ($arg2, $arg2->bases) {
        my $id2 = $obj2->{ID};
        next unless $actor->{$when}{$verb}{$id1}{$id2};
        my $reactions = $actor->{$when}{$verb}{$id1}{$id2};
        # Add the reactions to the master list.
        push @react1, @{ $reactions->[0] }; # -1
        push @react2, @{ $reactions->[1] }; # normal
        unshift @react3, @{ $reactions->[2] };  # 1
      }
    }
  }
  # Now there are three lists of reactions. Execute them all!
  my $code = 1;
  foreach (@react1, @react2, @react3) {
    # For now, those fancy scope conditions won't work.
    $code = $_->{Reaction}->($subj, $verb, $arg1, $arg2);  # Ain't we fancy?
    last if $code == -1;
  }
  return $code; # Yay.
}

sub render {
  my $self = shift;
  # Here be dragons... We'll resolve em into _SYMBOL_ and _COLOR_!
  $self->{Type} = $Game->{UI}{Tiles}{ $self->{_} };
  my ($symbol, $color);
  # The order: Character, top inventory item, and then tile.
  if ($self->{Char}) {
    $symbol = $self->{Char}->g("Symbol");
    $color = $self->{Char}->g("Color");
  } elsif ($self->{Inv}->get(-1)) {
    $symbol = $self->{Inv}->get(-1)->g("Symbol");
    $color = $self->{Inv}->get(-1)->g("Color");
  } else {
    $symbol = $Game->{UI}{Tiles}{ $self->{_} }{Symbol};
    $color = $Game->{UI}{Tiles}{ $self->{_} }{Color};
    $symbol = $self->{Symbol} if $self->{Symbol};
    $color = $self->{Color} if $self->{Color};
  }
  $color ||= "grey";
  $self->{_SYMBOL_} = $Game->{UI}{Interface}->trans_symbol($symbol);
  ($self->{_ATTRIB_}, $self->{_COLOR_})
    =
  $Game->{UI}{Interface}->trans_color($color);
}

sub opposite {
  my $dir = shift;
  return "N" if $dir eq "S";
  return "S" if $dir eq "N";
  return "E" if $dir eq "W";
  return "W" if $dir eq "E";
}

sub define {
  my ($name, $obj, $actions) = @_;
  # First set up all the Actions, Routines, and Pre Checks
  my $package = (caller)[0];
  no strict "refs";
  # Actions
    foreach (@$actions) {
      $obj->{Actions}{$_} = \&{"${package}::$_"};
    }
  # Routines and Pre Checks
    foreach (keys %{ $package . "::" }) {
      if (m/^UTIL_/) {
        my $entry = $_;
        $entry =~ s/^UTIL_//;
        $obj->{Routines}{$entry} = \&{"${package}::$_"};
      } elsif (m/^PRE_/) {
        my $entry = $_;
        $entry =~ s/^PRE_//;
        $obj->{Checks}{$entry} = \&{"${package}::$_"};
      }
    }
  use strict "refs";
  # Then stick in the templates list.
  $Game->{Templates}{$name} = $obj;
  # And content
  $Game->{Content}{$name} = $obj;
  return 1;
}

sub roll {
  # Why the heck are we so versatile? I'll end up using ONE style.
  my ($rolls, $sides);
  my $in = shift();
  $in =~ s/^(\d)+d(\d+)//;
  ($rolls, $sides) = ($1, $2);
  # Do we have a base?
  my $sum = $in || 0;
  foreach (1 .. $rolls) {
    $sum += random(1, $sides);
  }
  return $sum;
}

sub min {
  my ($iter, $min, $max) = @_;
  $iter = 2 if $iter < 2; # Or we're USELESS
  my ($last, $cur);
  foreach (1 .. $iter) {
    $cur = random($min, $max);
    $last = $cur if (!defined $last) or $cur < $last;
  }
  return $last;
}

sub max {
  my ($iter, $min, $max) = @_;
  $iter = 2 if $iter < 2; # Or we're USELESS
  my ($last, $cur);
  foreach (1 .. $iter) {
    $cur = random($min, $max);
    $last = $cur if (!defined $last) or $cur > $last;
  }
  return $last;
}

sub delrand {
  my $ls = shift;
  debug "Empty list for delrand? YOU BASTARD.", caller unless @$ls;
  my $n = random(0, $#{ $ls });
  return splice(@$ls, $n, 1);
}

42;
