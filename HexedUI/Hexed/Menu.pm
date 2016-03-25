package HexedUI::Hexed::Menu;

# There can only be one of many... so let's choose it

use strict;
use warnings;
use HexedUI::Util;

use constant max_pad_items => 5120;

use parent "HexedUI::Cursed::Window";

# Create and return a new menu window.
sub spawn {
  my $self = shift;

  $self->{KeyHandler} = delete $self->{Opts}{KeyHandler} // sub {};
  $self->bindq(delete $self->{Opts}{Queue}) if $self->{Opts}{Queue};
  $self->{Filter} = delete $self->{Opts}{Filter};

  $self->ui->install_keyhandler($self, \&keyhandler);

  $self->{Offset} = 0;
}

sub bindq {
  my ($self, $q) = @_;
  $self->{Queue} = $q;
  $self->{Queue}->hook(HexedMenu => $self, \&queue_hook);
  $self->on_resize;
  $self->draw;
}

# Need a new pad please
sub on_resize {
  my $self = shift;

  delwin($self->{Pad}) if $self->{Pad}; # Avoid memory leak. Thanks, Bryan Henderson.
  $self->{Pad} = newpad(max_pad_items, $self->{Width});


  my @ls = $self->all;
  if ($self->{Queue}) { # TODO because at boot when this is called spastically, freaks out
    $self->{Queue}->clear;
    # The callback would flip us out!
    $self->{Batch} = 1;
    $self->{Queue}->add($_) foreach @ls;
    delete $self->{Batch};
  }
}

sub all {
  my $self = shift;
  return unless $self->{Queue};
  return $self->{Queue}->all;
}

# Overloaded... Sort of. We're the method that actually prints to the screen. Through pads.
sub windraw {
  my $self = shift;

  return unless $self->{Queue};
  copywin($self->{Pad}, $self->{Win},
	  $self->{Offset}, 0,         # Offset in the pad
	  $self->{Y1}, $self->{X1},   # Where in window
	  $self->{Y2} - 1, $self->{X2} - 1,
    0
	);
}

# Provide movement functionality for the menu.
# TODO: real queue active
sub keyhandler {
  my ($self, $key) = @_;

  my $act = $self->ui->key($key);
  if ($act eq "down") {
    $self->{Queue}->move_down if $self->{Queue};
  } elsif ($act eq "up") {
    $self->{Queue}->move_up if $self->{Queue};
  } elsif ($act eq "first") {
    $self->{Queue}->move_first if $self->{Queue};
  } elsif ($act eq "last") {
    $self->{Queue}->move_last if $self->{Queue};
  } elsif ($act eq "page_up") {
    my $to = $self->{Queue}->active - $self->{Height} + 1;
    $to = 0 if $to < 0;
    $self->{Queue}->move($to);
  } elsif ($act eq "page_down") {
    my $to = $self->{Queue}->active + $self->{Height} - 1;
    $to = $self->{Queue}->all - 1 if $to > $self->{Queue}->all - 1;
    $self->{Queue}->move($to);
  } elsif ($key =~ m/^[a-zA-Z]$/ and $self->{Queue}) {
    # Search! TODO color tags in the way
    for ($self->{Queue}->active + 1 .. $self->{Queue}->all - 1, 0 .. $self->{Queue}->active) {
      next unless $self->{Queue}->get($_) =~ m/^$key/i;
      $self->{Queue}->move($_);
      last;
    }
  } else {
    $self->{KeyHandler}->($self, $key);
  }
}

# Every time something happens to our queue, do something. Potentially. Yes.
sub queue_hook {
  my $queue = shift;
  my $win = shift;
  my $cmd = shift;

  if ($cmd eq "add") {
    my $y = $#{ $queue->{Queue} };
    my %opts;
    %opts = (-reversed => 1) if $y == $queue->active;
    $win->colorwrite(%opts, $win->{Pad}, $win->render(-1), $y, 0);
  } elsif ($cmd eq "del") {
    my $old = shift;
    # TODO
  } elsif ($cmd eq "move") {
    my $prev = shift;
    $win->colorwrite($win->{Pad}, $win->render($prev), $prev, 0);  # De highlight
    my $now = $queue->active;
    $win->colorwrite(-reversed => 1, $win->{Pad}, $win->render($now), $now, 0);
  } elsif ($cmd eq "insert") {
    my $y = shift;
    $win->{Pad}->move($y, 0);
    $win->{Pad}->insertln;
    $win->colorwrite($win->{Pad}, $win->render($y), $y, 0);
  } elsif ($cmd eq "modded") {
    my $i = shift;
    my @opts = ();
    @opts = (-reversed => 1) if $i == $queue->active;
    $win->colorwrite(@opts, $win->{Pad}, $win->render($i), $i, 0);
  }

  # Scroll if we need to. For now, just center the current entry.
  if ($queue->all <= $win->{Height}) {
    $win->{Offset} = 0;
  } else {
    my $middle = int($win->{Height} / 2);
    if ($queue->active >= $middle) {
      $win->{Offset} = $queue->active - $middle;
      # And cap it so we don't run off end of entries. Don't ask me how I figured out this.
      my $cap = $queue->all - $middle - $middle;
      $win->{Offset} = $cap if $win->{Offset} > $cap;
    } else {
      $win->{Offset} = 0;
    }
  }

  $win->draw unless $win->{Batch};
}

# Wrap around a filter
sub render {
  my ($self, $y) = @_;
  my $entry = $self->{Queue}->get($y);
  return $self->{Filter} ? $self->{Filter}->($self, $entry) : $entry;
}

42;
