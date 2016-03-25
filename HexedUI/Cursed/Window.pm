package HexedUI::Cursed::Window;

# TODO havent cleaned

use strict;
use warnings;
use HexedUI::Util;

# Create and return a new window.
sub init {
  my ($class, %dat) = @_;
  my $self = bless \%dat, $class;
  $self->spawn;   # Each window type has its stuff
  if (%{ $self->{Opts} }) {
    debug $self->{Opts};
    die "unhandled options!";
  }
  delete $self->{Opts};
  $self->{Panel} = new_panel($self->{Win});
  return $self;
}

# Simply refresh the window
sub draw {
  my $self = shift;

  # Delegate most of the work to them.
  $self->windraw if $self->can("windraw");

  ## And move the cursor to its spot if its on.
  #if (my $cursor = $self->ui->{_Cursor}[-1]) {
  #  $cursor->[0]{Panel}->top_panel;
  #  debug $cursor->[0]{Panel}->panel_above;
  #  # # try top_panel
  #  $cursor->[0]{Win}->move($cursor->[1], $cursor->[2]);
  #}

  update_panels();
  doupdate();
}

# Give a reference to the HexedUI singleton
sub ui {
  my $self = shift;
  return $self->{_HexedUI};
}

# These are nice cause they're "encapsulated"
sub height {
  my $self = shift;
  return $self->{Height};
}

sub width {
  my $self = shift;
  return $self->{Width};
}

# Register the cursor as being somewhere... until it's not.
sub cursor {
  my ($self, $y, $x) = @_;
  if (defined $y) {
    #curs_set(1);
    if ($self->{Cursor}) {
      # Update it
      my ($entry) = grep { $_->[0]{Name} eq $self->{Name} } @{ $self->ui->{_Cursor} };

      # We don't need to undraw because our only user TODO so far is Prompt and they
      # standend and redraw the line anyway, so yeah.

      $entry->[1] = $y;
      $entry->[2] = $x;
    } else {
      # Register a new one
      $self->{Cursor} = 1;
      push @{ $self->ui->{_Cursor} }, [$self, $y, $x];
    }
    # Draw!
    my $blink = $self->{Win}->inch($y, $x);
    $self->{Win}->standend;
    $self->{Win}->attron(A_STANDOUT()); # Actual blinking without a terminal cursor is meh
    $self->{Win}->addch($y, $x, $blink);
  } else {
    # Nuke it
    $self->{Cursor} = 0;
    my @new;
    foreach (@{ $self->ui->{_Cursor} }) {
      push @new, $_ unless $_->[0]{Name} eq $self->{Name};
    }
    $self->ui->{_Cursor} = \@new;
    #curs_set(0) unless @new;
  }
}

# Draw the window's border, if necessary.
sub frameit {
  my $win = shift;
  if (my $new = shift) {
    $win->{Border} = $new;
  }
  return unless my $color = $win->{Border};
  $win->{Win}->standend;
  $win->{Win}->attron( paint($color) );
  $win->{Win}->box(0, 0);
  $win->draw;
}

# Yes, we can move popups and stuff!
# Note move_panel returns 0 upon success, hence the unless
sub mvright {
  my $win = shift;
  unless ($win->{Panel}->move_panel($win->{AbsPosY}, $win->{AbsPosX} + 1)) {
    $win->{X1}++;
    $win->{X2}++;
    $win->{AbsPosX}++;
  }
}

sub mvleft {
  my $win = shift;
  unless ($win->{Panel}->move_panel($win->{AbsPosY}, $win->{AbsPosX} - 1)) {
    $win->{X1}--;
    $win->{X2}--;
    $win->{AbsPosX}--;
  }
}

sub mvup {
  my $win = shift;
  unless ($win->{Panel}->move_panel($win->{AbsPosY} - 1, $win->{AbsPosX})) {
    $win->{Y1}--;
    $win->{Y2}--;
    $win->{AbsPosY}--;
  }
}

sub mvdown {
  my $win = shift;
  unless ($win->{Panel}->move_panel($win->{AbsPosY} + 1, $win->{AbsPosX})) {
    $win->{Y1}++;
    $win->{Y2}++;
    $win->{AbsPosY}++;
  }
}

# Generalized to work anywhere! Draws a string to a window (or a pad), paying attention to
# color tags and other stuff.
sub colorwrite {
  my ($self, $opts, $win, $line, $y, $x) = args @_;

  # Handle length
  my $copy = $line;
  $copy =~ s/<([\w\/]+)>//g;  # Color tags
  if (length($copy) > $self->{Width}) {
    # TODO: substr?
    debug "$line is too long for this window";
    $copy = substr($copy, 0, $self->{Width});
    #return;
  }
  my $pad = $opts->{maxpad} ? $opts->{maxpad} - length($copy) : $self->{Width} - length($copy) - $x;
  $line .= " " x $pad;

  # Split by <\w+> and print the color codes in the right spots.
  $win->standend;
  my $lastcolor;
  $win->attron(A_REVERSE()) if $opts->{reversed};
  foreach my $string (split(/(<[\w\/]+>)/, $line)) {
    next unless $string;
    if ($string =~ m/<([\w\/]+)>/) {
      $win->standend;
      $win->attron(A_REVERSE()) if $opts->{reversed};
      $win->attron( paint($1) );
      $lastcolor = $1;
    } else {
      $win->addstr($y, $x, $string);
      $x += length $string;
    }
  }
  return $lastcolor;
}

42;
