package HexedUI::Hexed::Form;

use strict;
use warnings;
use HexedUI::Util;

# If you want a statusbar type doohickey with counters or constantly changing data amidst
# static labels, use us!

use parent "HexedUI::Cursed::Window";

use POSIX ("ceil");

# Create and return a new window.
sub spawn {
  my $self = shift;
  $self->{Cnt} = 0;
  $self->{Original} = [];

  # TODO: make these entry-specific
  $self->{Center} = delete $self->{Opts}{Center};
  $self->{WriteOpts} = [-reversed => 1] if delete $self->{Opts}{Reverse};

  $self->{Withs} = delete $self->{Opts}{Withs} // {};
  $self->add_entry(@$_) foreach @{ $self->{Opts}{Entries} };
  delete $self->{Opts}{Entries};
}

# Redraw all entries
sub on_resize {
  my $self = shift;
  $self->{Cnt} = 0;
  foreach (@{ $self->{Original} }) {
    $self->add_entry(-resizing => 1, @$_);
  }
}

# An entry basically looks like "Static stuff now var sub 1 is _, and a progess bar *",
# except you can also squeeze in a few entries on the same vertical line and stuff.
sub add_entry {
  my ($self, $args, @entries) = args @_;
  my $resizing = delete $args->{resizing};
  push @{ $self->{Original} }, [ map { [@$_] } @entries ] unless $resizing;
  my $y = $self->{Cnt}++;
  my $x = 0;
  my $split = @entries;
  foreach my $entry (@entries) {
    my @copy = @$entry;
    my $id = shift @copy;
    my ($string, $opts) = args @copy;

    my $copy = $string;
    $copy =~ s/<(\w+)>//g;  # Color tags
    if ($self->{Center}) {
      # Do it the easy way please
      $string = (" " x center($copy, $self->{Width})) . $string;
    }

    my $old = $self->{Entries}{$id}{Old};

    $self->{Entries}{$id} = {
      String => $string,
      Bars   => $opts->{bars} // [],
      With   => $opts->{with} // $self->{Withs}{$id},
      Y      => $y,
      X      => int($self->{Width} / $split) * $x++,
      Pad    => int($self->{Width} / $split)
    };
    
    if ($resizing) {
      # Only draw if we have something to draw
      next unless $old;
      $self->{Entries}{$id}{Old} = $old;
      $self->update($id);
    }
  }
  $self->draw;
}

# Fill an entry with new data for the var sub bits or progress bar
sub update {
  my ($self, $entry, @with) = @_;
  my $data = $self->{Entries}{$entry};
  die "no $entry form entry" unless $data;
  
  # Obtain our data
  unless (@with) {
    if ($data->{With}) {
      @with = $data->{With}->();
    } else {
      # Use old value, we're probably resizing
      return unless $data->{Old};
      @with = @{ $data->{Old} };
    }
  }
  $data->{Old} = [@with];
  my @bars = @{ $data->{Bars} };

  my $string = $data->{String};
  my $off = 0;  # When we add something in, have to count differently
  for my $i (0 .. length($string)) {
    my $this = substr($string, $i + $off, 1);
    if ($this eq "_") {
      my $value = shift @with;
      # Sub in a value
      substr($string, $i + $off, 1, $value);
      $off += length($value) - 1; # -1 because we used to have a _ there
    } elsif ($this eq "*") {
      # Sub in a colored bar
      my $of = shift @with;
      my $max = shift @with;
      my $len = shift @bars;
      my $how = ceil(($of * $len) / $max);
      my $color;
      if ($of / $max >= .8) {
        $color = "Green";
      } elsif ($of / $max >= .4) {
        $color = "yellow";
      } elsif (!$how) {
        $color = "yellow/red";
      } else {
        $color = "Red";
      }
      my $bar = "<$color>" . "*" x ($how) . "<grey>" . "*" x ($len - $how);
      substr($string, $i + $off, 1, $bar);
      $off += length($bar) - 1; # -1 because we used to have a * there
    }
  }

  $self->colorwrite(
    -maxpad => $data->{Pad}, @{ $self->{WriteOpts} },
    $self->{Win}, $string, $self->{Y1} + $data->{Y}, $self->{X1} + $data->{X}
  );

  $self->draw;
}

42;
