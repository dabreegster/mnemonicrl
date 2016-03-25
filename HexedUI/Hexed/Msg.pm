package HexedUI::Hexed::Msg;

use strict;
use warnings;
use HexedUI::Util;

use constant max_pad_items => 5120;

use parent "HexedUI::Cursed::Window";

use PUtil::Queue;

# Create and return a new menu window.
sub spawn {
  my $self = shift;

  $self->{Queue} = PUtil::Queue->new;

  $self->{Offset} = $self->{LineCnt} = 0;
  $self->on_resize;
}

# TODO make this a queue hook thing? nah cause noninteractive..
sub add {
  my ($self, $opts, $msg) = args @_;
  my $y = $self->{LineCnt};
  cleanlines($msg) unless $opts->{preserve};
  #log_this("MSG: $msg");  # TODO better place
  $self->{Queue}->add($msg);

  my @lines = wrap($self->{Width} - 1, $msg);
  $self->{LineCnt} += @lines;

  # TODO: tmp fix for reaching max_pady is to erase all the old stuff. - 1 = my paranoia
  # Still hard to fix.. shift queue is easy, but we gotta move all those lines up in the
  # pad.. till we figure out how, then no idea.
  if ($self->{LineCnt} >= max_pad_items - 1) {
    $self->{Queue}{Queue} = [];
    erase($self->{Pad});
    $self->{LineCnt} = 0;
  }

  # Scroll if we need to.
  if ($self->{LineCnt} <= $self->{Height}) {
    $self->{Offset} = 0;
  } else {
    $self->{Offset} = $self->{LineCnt} - $self->{Height};
  }

  # Draw it
  $self->{Pad}->standend;

  my $color;
  foreach my $line (@lines) {
    # Carry over the color to all lines in one message
    $line = "<$color>$line" if $color;
    $color = $self->colorwrite($self->{Pad}, $line, $y++, 0);
  }

  # Dear lord no, dont do that here!
  #$self->draw;
}

# Scroll the message log up if we can
sub scroll_up {
  my $self = shift;
  if ($self->{Offset} != 0) {
    $self->{Offset}--;
    $self->draw;
  }
}

# Scroll the message log down if we can
sub scroll_down {
  my $self = shift;
  if ($self->{LineCnt} > $self->{Height} and $self->{Offset} != $self->{LineCnt} - $self->{Height}) {
    $self->{Offset}++;
    $self->draw;
  }
}

# Need a new pad please
sub on_resize {
  my $self = shift;
  $self->{LineCnt} = 0;
  delwin($self->{Pad}) if $self->{Pad}; # Avoid memory leak. Thanks, Bryan Henderson.
  $self->{Pad} = newpad(max_pad_items, $self->{Width});
  my @ls = $self->all;
  $self->{Queue}{Queue} = [];  # add() puts them on the queue, we don't want to multiply
  $self->{Queue}->add($_) foreach @ls;
}

# People want this. TODO dubious.
sub all {
  my $self = shift;
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

# basically just new again :P
sub clean {
  my $self = shift;

  $self->{Queue} = PUtil::Queue->new;

  $self->{Offset} = $self->{LineCnt} = 0;
  $self->on_resize;
  $self->draw;
}

42;
