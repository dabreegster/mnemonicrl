package HexedUI::Hexed::Prompt;

# We're probably the ugly duckling everybody will use. Take one-line input, allowing
# readlineish editing. Too bad the cursor stuff is all broken, or we'd look really nice.

use strict;
use warnings;
use HexedUI::Util;

use parent "HexedUI::Cursed::Window";

# Create and return a new prompt window.
sub spawn {
  my $self = shift;
  $self->{MaxIn} = delete $self->{Opts}{MaxIn};
}

sub on_resize {
  my $self = shift;
  $self->{X} = @{ $self->{In} };
  # Stay to the right
  $self->{XOff} = @{ $self->{In} } - $self->{Width} + 1;
}

# Go through the entire prompting process
sub prompt {
  my ($self, $query, $limit) = @_;
  # TODO: messy debugging, handling, testing
  die "prompt query is too long!" if length($query) > $self->{Width};
  die "prompt limit is too long!" if $limit > $self->{Width};

  $self->ui->start_in;

  # Set the prompt title.
  # TODO: messy.. is this prompt's job?
  $self->{Win}->standend;
  $self->{Win}->attron(A_REVERSE());
  # Center the query.
  my $x = center($query, $self->{Width});
  $self->{Win}->addstr($self->{Y1}, $self->{X1} + $x, $query);
  $self->draw;

  $self->{Y1}++;
  $self->start_prompt($limit);
  
  my $input = "";
  while (1) {
    my $key = $self->ui->wait_input;
    if ($self->ui->key($key) eq "ok") {
      last;
    } elsif ($self->ui->key($key) eq "cancel") {
      $input = ":cancel";
      last;
    } else {
      $self->nextkey($key);
    }
  }

  $input = $input eq ":cancel" ? undef : $self->stop_prompt;
  $self->ui->stop_in;

  return $input;
}

# The beginning of the sequence. Turn on the cursor and reset our data.
sub start_prompt {
  my ($self, $limit) = @_;
  $limit ||= $self->{MaxIn};

  # Turn the cursor on and start the magic loop, maaan.
  $self->{Win}->standend;
  $self->cursor($self->{Y1}, $self->{X1});
  $self->draw;

  $self->{In} = [];
  $self->{XOff} = 0;
  $self->{X} = 0;
  $self->{Limit} = $limit;
}

# If we don't want to take exclusive control of the keyboard, can be called manually.
# Otherwise the full prompting procedure uses us anyway.
sub nextkey {
  my ($self, $key) = @_;
  
  # Grab our vars
  my $x = $self->{X};
  my @in = @{ $self->{In} };

  my $act = $self->ui->key($key);
  if (!defined$key) {
    #debug "blank key to nextkey?! we shouldnt use this to redraw anymore";
    # I use it for resizing, I guess I should separate draw functionality
    # Blank key, do nothing, just redraw.
  } elsif ($act eq "left") {
    $x-- unless $x == 0;
    $self->{XOff}-- if $self->{XOff} == $x;
  } elsif ($act eq "right") {
    $x++ unless $x == @in;  # We can move one past the next character
    $self->{XOff}++ if $self->{XOff} + $self->{Width} == $x;
  } elsif ($act eq "first") {
    $x = 0;
    $self->{XOff} = 0;
  } elsif ($act eq "last") {
    $x = @in;
    $self->{XOff} = @in - $self->{Width} + 1;
  } elsif ($act eq "backspace") {
    unless ($x == 0) {
      splice @in, $x - 1, 1;
      $x--;
      $self->{XOff}--;
      $self->{Win}->move($self->{Y1}, $self->{X1} + $x - 1);
    }
  } elsif ($act eq "delete") {
    unless ($x == @in) {
      splice @in, $x, 1;
      $self->{XOff}--;
    }
  } elsif ($key =~ m/<.+>/) {
    # Don't do anything with it
  } else {
    unless (@in == $self->{Limit}) {
      splice @in, $x, 0, $key;
      $x++;
      $self->{XOff}++ if $x > $self->{XOff} + $self->{Width} - 1;
    }
  }
  $self->{XOff} = 0 if $self->{XOff} < 0;

  # Store our vars
  $self->{X} = $x;
  $self->{In} = \@in;

  $self->draw;
}

sub windraw {
  my $self = shift;
  $self->{Win}->standend;   # In case the border redraw messed with it

  my $in = $self->{In};
  return unless $in;
  my @in = @$in;
  # Scroll horizontally
  my $sofar;
  if (@in < $self->{Width}) {
    $sofar = join("", @in);
    $sofar .= " " x ($self->{Width} - @in);
  } else {
    $sofar = join("", @in[$self->{XOff} .. $self->{XOff} + $self->{Width} - 2]);
  }

  $self->{Win}->addstr($self->{Y1}, $self->{X1}, $sofar);
  $self->cursor($self->{Y1}, $self->{X1} + $self->{X} - $self->{XOff});
}

sub stop_prompt {
  my $self = shift;

  my $input = join "", @{ $self->{In} };
  delete $self->{X};
  delete $self->{XOff};
  delete $self->{Limit};
  delete $self->{In};

  # And clean up the window
  $self->cursor();  # Get rid of it or seeeeegfaaaault!
  $self->{Win}->move($self->{Y1}, $self->{X1});
  $self->{Win}->clrtoeol;
  $self->frameit;
  return $input;
}

42;
