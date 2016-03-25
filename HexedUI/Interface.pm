package HexedUI::Interface;

use strict;
use warnings;
use HexedUI::Util;

sub POE::Kernel::CATCH_EXCEPTIONS () { 0 }  # thanks dngnor, I like my errors :)

use POE ("Wheel::Curses");
use Time::HiRes ("time");

# Extend the singleton!
use parent "HexedUI::Cursed::Frame";

# The HexedUI singleton maintains the POE Curses session, wraps terminal resizing and key
# input, and manages windows.
sub cast {
  my ($class, $layout) = @_;

  my $self = bless {
    _Keymap      => {},
    _Keyhandlers => [],
    _Cursor      => [],
    _Layout      => $layout,
    _Tmp         => 0, # Every time we make a new temporary popup/whatever, keep count
    _TmpKeys     => 0,
    _Killswitch  => delete $layout->{on_exit},
    _DrawLag     => delete $layout->{FPS}  // 1.0  # Redraw every 1.0 second(s)
  }, $class;

  $self->keymap(delete $layout->{Keymap}) if $layout->{Keymap};

  my $last_t = time;
  # Set up the main event loop magic.
  POE::Session->create(
    inline_states => {
      _start => sub {
        $_[HEAP]{Curses} = POE::Wheel::Curses->new(
          InputEvent => "keystroke_handler"
        );
        $_[HEAP]{UI} = $self;
        $_[KERNEL]->alias_set("hexedui");
        $_[KERNEL]->sig(WINCH => "term_resize");
        $self->{_DrawAlarm} = POE::Kernel->delay_set("draw_tick" => $self->{_DrawLag});
      },
      _stop => sub {
        # TODO: portable please
        system("clear");
        endwin();
        exit;
      },
      keystroke_handler => sub {
        my $key = $_[ARG0];
        my $ui = $_[HEAP]{UI};

        if ($key eq KEY_MOUSE) {
          my $e = 0;
          getmouse($e);
          # Nicked from PoCo::Curses source, which was nicked from Curses::UI :P
          my ($id, $x, $y, $z, $bstate) = unpack("sx2i3l", $e);
          $ui->{_Mousehandler}->($y, $x) if $ui->{_Mousehandler};
          return;
        }

        if ($key lt " ") {
          $key = "<" . uc(unctrl($key)) . ">";
        } elsif ($key =~ m/^\d{2,}$/) {
          $key = "<" . uc(keyname($key)) . ">";
        }
        # Usable names would be great
        my %map = (
          "<KEY_BACKSPACE>" => "<BACKSPACE>",
          ""              => "<BACKSPACE>",
          "<^[>"            => "<ESCAPE>",
          "<^M>"            => "<ENTER>",
          "<^I>"            => "<TAB>",
          "<KEY_DC>"        => "<DELETE>"
        );
        $key = $map{$key} if $map{$key};

        if ($key eq "<^C>") {
          delete $_[HEAP]{curses};
          $ui->{_Killswitch}->() if $ui->{_Killswitch};
          exit;
        } else {
          die "no keyhandler\n" unless @{ $ui->{_Keyhandlers} };
          $ui->{_Keyhandlers}[-1]{Handler}->($ui->{_Keyhandlers}[-1]{Win}, $key);
        }
      },
      term_resize => sub {
        my $ui = $_[HEAP]{UI};
        endwin();   # This sequence is documented curses magic that reallocates the screen
        refresh();
        $ui->_setup;
      },
      draw_tick => sub {
        my $ui = $_[HEAP]{UI};
        my $win = $ui->{_DrawTimed};
        if ($win and $win->{DrawPad}) {
          $win->draw;
          $win->{DrawPad} = 0;
        }
        my $this_t = time;
        my $elapsed = $this_t - $last_t;
        my $lag = $ui->{_DrawLag} - $elapsed;
        #debug "$elapsed since last tick, it should be $ui->{_DrawLag}";
        if ($lag < 0) {
          #debug "WARNING we're slow by " . abs($lag);
          $lag = 0; # Still gotta keep POE alarm going
        } else {
          # POE timers aren't exact and there could've easily been precision issues, so
          # don't sleep for the entire time
          $lag *= 0.9;
        }
        $last_t = $this_t;
        $ui->{_DrawAlarm} = POE::Kernel->delay_set("draw_tick" => $lag);
      }
    }
  );

  # Yo mama uses a monochrome terminal.
  my @colors = ( qw(BLACK RED GREEN YELLOW BLUE MAGENTA CYAN WHITE) );
  # Magically initialize all possible combos of foregrounds and backgrounds.
  my $cnt = 0;
  no strict "refs";   # Naughty!
  foreach my $bg (@colors) {
    foreach my $fg (@colors) {
      init_pair(++$cnt, &{ "COLOR_$fg" }, &{ "COLOR_$bg" });
    }
  }

  # Mouse! Only seems to work in konsole/without screen for now
  mousemask(ALL_MOUSE_EVENTS, {});

  $self->_setup;

  return $self;
}

# Add new keys from a file
sub keymap {
  my ($self, $file) = @_;
  my $mode;
  foreach my $line (slurp($file)) {
    next unless $line;
    next if $line =~ m/^#/;
    if ($line =~ m/\[(\w+)\]/) {
      $mode = $1;
    } else {
      my ($key, $cmd) = split(/\s*=\s*/, $line);
      $key ||= " "; # Cause we just split by it :P
      die "key before mode!\n" unless $mode;
      $cmd = [split(/ /, $cmd)] if $cmd =~ m/ /;
      $self->{_Keymap}{$mode}{$key} = $cmd;
    }
  }
}

# Translate a key to a UI function
sub key {
  my $self = shift;
  my ($mode, $key);
  if (@_ == 2) {
    ($mode, $key) = @_;
  } else {
    $key = shift;
    $mode = "UI";
  }
  return $self->{_Keymap}{$mode}{$key} // "";
}

# At start and after resize
sub _setup {
  my $self = shift;

  # Set up curses stuff.
  getmaxyx(my $rows, my $cols);
  $self->{_MaxDims} = [$rows, $cols];
  curs_set(0);

  # Create the windows from the given layout.
  my @last; # (re-)draw the temporary windows last for proper Z order, the panels get lost
  while (my ($win, $dat) = each %{ $self->{_Layout} }) {
    if ($win =~ m/^Tmp/) {
      push @last, [$win, $dat];
    } else {
      $self->_make_win($win => { %$dat });  # Make a copy
    }
  }
  $self->_make_win($_->[0] => { %{ $_->[1] } }) foreach @last;
}

# Any window that does input (one at a time gets it) needs to register a keyhandler
sub install_keyhandler {
  my ($self, $win, $sub) = @_;
  push @{ $self->{_Keyhandlers} }, { Win => $win, Handler => $sub };
}

# Destroy all of a window's registered keyhandlers.
sub remove_keyhandler {
  my ($self, $name) = @_;
  my @new;
  # Don't modify arrays in loops
  foreach (@{ $self->{_Keyhandlers} }) {
    push @new, $_ unless $_->{Win}{Name} eq $name;
  }
  @{ $self->{_Keyhandlers} } = @new;
}

# Starts everything. The user can do this themselves, it doesn't matter, as long as POE
# runs.
sub start {
  $poe_kernel->run;
  exit;
}

# Do a blocking style "wait for input" without actually blocking.
sub wait_input {
  my $self = shift;
  $poe_kernel->run_one_timeslice until defined $self->{_BlockingInput};
  return delete $self->{_BlockingInput};
}

# Wrap a quick keymap to simply return input to wait_input(). Don't layer us -- one at a
# time please.
sub start_in {
  my $self = shift;
  my $tmp = ++$self->{_TmpKeys};
  $self->install_keyhandler({ Name => "Tmp$tmp" }, sub {
    my (undef, $key) = @_;
    # $_[0] is normally the window, but since our window is bogus anyway ("Tmp"), use the
    # closure magic stuff to get at the singleton
    $self->{_BlockingInput} = $key;
  });
}

# Remove that temporary key returner.
sub stop_in {
  my $self = shift;
  my $tmp = $self->{_TmpKeys}--;
  $self->remove_keyhandler("Tmp$tmp");
}

# Who're we redrawing every N seconds?
sub draw_timed {
  my ($self, $win) = @_;
  $self->{_DrawTimed} = $win;
}

42;
