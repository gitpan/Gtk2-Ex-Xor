# Copyright 2007, 2008 Kevin Ryde

# This file is part of Gtk2-Ex-Xor.
#
# Gtk2-Ex-Xor is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 3, or (at your option) any later
# version.
#
# Gtk2-Ex-Xor is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with Gtk2-Ex-Xor.  If not, see <http://www.gnu.org/licenses/>.

package Gtk2::Ex::Lasso;
use strict;
use warnings;
use Carp;
use List::Util qw(min max);
use Scalar::Util;

use Gtk2;
use Gtk2::Ex::Xor;

our $VERSION = 2;

# set this to 1 for some diagnostic prints
use constant DEBUG => 0;


use constant DEFAULT_LINE_STYLE => 'on_off_dash';

use Glib::Object::Subclass
  Glib::Object::,
  signals => { moved   => { param_types => [ 'Glib::Int',
                                             'Glib::Int',
                                             'Glib::Int',
                                             'Glib::Int' ],
                            return_type => undef },
               ended   => { param_types => [ 'Glib::Int',
                                             'Glib::Int',
                                             'Glib::Int',
                                             'Glib::Int' ],
                            return_type => undef },
               aborted => { param_types => [ ],
                            return_type => undef },
             },
  properties => [ Glib::ParamSpec->object
                  ('widget',
                   'widget',
                   'Widget to draw the lasso on.',
                   'Gtk2::Widget',
                   Glib::G_PARAM_READWRITE),

                  Glib::ParamSpec->boolean
                  ('active',
                   'active',
                   'True if lassoing is being drawn, moved, etc.',
                   0,
                   Glib::G_PARAM_READWRITE),

                  Glib::ParamSpec->scalar
                  ('foreground',
                   'foreground',
                   'The colour to draw the lasso, either a string name, an allocated Gtk2::Gdk::Color object, or undef for the widget\'s style foreground.',
                   Glib::G_PARAM_READWRITE),

                  Glib::ParamSpec->scalar
                  ('cursor',
                   'cursor',
                   'Cursor while lassoing, anything accepted by Gtk2::Ex::WidgetCursor, default \'hand1\'.',
                   Glib::G_PARAM_READWRITE),

                ];


# not wrapped as of Gtk2-Perl 1.183
use constant GDK_CURRENT_TIME => 0;


sub INIT_INSTANCE {
  my ($self) = @_;
  $self->{'button'} = 0;
  $self->{'cursor'} = 'hand1';
}

sub FINALIZE_INSTANCE {
  my ($self) = @_;
  if ($self->{'active'}) {
    # don't emit 'ended' or 'aborted' during destroy
    _end ($self);
  }
}

sub SET_PROPERTY {
  my ($self, $pspec, $newval) = @_;
  my $pname = $pspec->get_name;
  my $oldval = $self->{$pname};

  if ($pname eq 'foreground') {
    if ($self->{'drawn'}) { _draw ($self); }
    if (my $gc = delete $self->{'gc'}) { Gtk2::GC->release ($gc); }
    $self->{$pname} = $newval;
    if ($self->{'active'}) { _draw ($self); }
    return;
  }

  $self->{$pname} = $newval;  # per default GET_PROPERTY

  if ($pname eq 'widget') {
    my $widget = $newval;
    Scalar::Util::weaken ($self->{$pname});
    $widget->add_events (['button-motion-mask',
                          'button-release-mask']);

    # require Gtk2::Ex::WidgetEvents;
    # $self->{'wevents'} = Gtk2::Ex::WidgetEvents->new ($widget,
    #                                                   ['button-motion-mask',
    #                                                    'button-release-mask',
    #

  } elsif ($pname eq 'active') {
    if ($newval && ! $oldval) {
      $self->start;
    } elsif ($oldval && ! $newval) {
      $self->abort;
    }

  } elsif ($pname eq 'cursor') {
    _update_widgetcursor ($self);
  }
}

sub start {
  my ($self, $event) = @_;
  my $widget = $self->{'widget'} or croak 'Lasso has no widget';
  if (DEBUG) { print "Lasso start\n"; }

  my $window = $widget->Gtk2_Ex_Xor_window
    or croak 'Lasso->start(): unrealized widget not (yet) supported';

  if (Scalar::Util::blessed($event) && $event->can('button')) {
    $self->{'button'} = $event->button;

  } elsif (! $self->{'grabbed'}) {
    my $status = Gtk2::Gdk->pointer_grab
      ($window,
       1,      # owner events
       ['pointer-motion-mask'],
       undef,  # no confine window
       undef,  # cursor
       _event_time($event));
    if (DEBUG) { print "  pointer_grab $status\n"; }
    if ($status eq 'success') {
      $self->{'grabbed'} = 1;
    } else {
      carp "Lasso->start(): cannot grab pointer: $status";
    }
    $self->{'button'} = 0;
  }

  if ($self->{'active'}) {
    if (DEBUG) { print "  already active\n"; }
    return;
  }

  $self->{'active'} = 1;
  _update_widgetcursor ($self);

  my $weak_self = $self;
  Scalar::Util::weaken ($weak_self);
  my $ref_weak_self = \$weak_self;
  require Glib::Ex::SignalIds;
  $self->{'signal_ids'} = Glib::Ex::SignalIds->new
    ($widget,
     $widget->signal_connect (motion_notify_event => \&_do_motion_notify,
                              $ref_weak_self),
     $widget->signal_connect (button_release_event => \&_do_button_release,
                              $ref_weak_self),
     $widget->signal_connect (grab_broken_event => \&_do_grab_broken,
                              $ref_weak_self),
     $widget->signal_connect_after (expose_event => \&_do_expose,
                                    $ref_weak_self),
     $widget->signal_connect_after (size_allocate => \&_do_size_allocate,
                                    $ref_weak_self));

  $self->{'snooper_id'} = Gtk2->key_snooper_install
    (\&_do_key_snooper, $ref_weak_self);

  my ($x, $y) = (Scalar::Util::blessed($event) && $event->can('x')
                 ? Gtk2::Ex::Xor::_event_widget_coords ($widget, $event)
                 : $widget->get_pointer);
  if (DEBUG) { print "  initial $x,$y\n"; }

  $self->{'x1'} = $x+1; # always initial "moved" emission
  $self->{'y1'} = $y;
  $self->{'x2'} = $x;
  $self->{'y2'} = $y;
  $self->{'drawn'} = 0;
  $self->notify ('active');
  _maybe_move ($self, $x,$y, $x,$y);
}

sub end {
  my ($self, $event) = @_;
  if (! $self->{'active'}) { return; }

  if (Scalar::Util::blessed($event)
      && ($event->isa('Gtk2::Gdk::Event::Button')
          || $event->isa('Gtk2::Gdk::Event::Motion'))) {
    _do_motion_notify ($self->{'widget'}, $event, \$self);
  }
  _end ($self, $event);
  $self->notify ('active');
  $self->signal_emit ('ended',
                      $self->{'x1'}, $self->{'y1'},
                      $self->{'x2'}, $self->{'y2'});
}

sub abort {
  my ($self, $event) = @_;
  if (DEBUG) { print "Lasso abort ",
                 ($self->{'active'}?" (already inactive)":""),"\n"; }
  if (! $self->{'active'}) { return; }
  _end ($self, $event);
  $self->notify ('active');
  $self->signal_emit ('aborted');
}

sub _end {
  my ($self, $event) = @_;
  $self->{'active'} = 0;
  $self->{'signal_ids'} = undef;

  my $widget = $self->{'widget'};
  if ($self->{'drawn'}) {
    if (DEBUG) { print "  undraw\n"; }
    _draw ($self);
    $self->{'drawn'} = 0;
  }

  _update_widgetcursor ($self);

  if (my $id = delete $self->{'snooper_id'}) {
    Gtk2->key_snooper_remove ($id);
  }
  if (delete $self->{'grabbed'}) {
    Gtk2::Gdk->pointer_ungrab (_event_time ($event));
  }
}

sub _update_widgetcursor {
  my ($self) = @_;

  if ($self->{'active'} && $self->{'cursor'}) {
    if ($self->{'wcursor'}) {
      $self->{'wcursor'}->cursor ($self->{'cursor'});
    } else {
      require Gtk2::Ex::WidgetCursor;
      $self->{'wcursor'}
        = Gtk2::Ex::WidgetCursor->new (widget => $self->{'widget'},
                                       cursor => $self->{'cursor'},
                                       active => 1);
    }
  } else {
    delete $self->{'wcursor'};
  }
}


sub _do_expose {
  my ($widget, $event, $ref_weak_self) = @_;
  my $self = $$ref_weak_self or return;
  if (DEBUG) { print "lasso expose $widget, active=",
                 $self->{'active'}||0,"\n"; }
  if ($self->{'drawn'}) {
    _draw ($self, $event->region);
  }
}

# 'motion-notify' on widget, and also called for $lasso->end if it gets a
# button or motion event
sub _do_motion_notify {
  my ($widget, $event, $ref_weak_self) = @_;
  my $self = $$ref_weak_self or return;

  # Do a get_pointer() to support 'pointer-motion-hint-mask'.
  # Maybe should use $display->get_state here instead of just get_pointer,
  # but the crosshair at present only works with the mouse, not an arbitrary
  # input device.
  my ($x, $y) = ($event->can('is_hint') # not in final button release event
                 && $event->is_hint
                 ? $widget->get_pointer
                 : Gtk2::Ex::Xor::_event_widget_coords ($widget, $event));
  _maybe_move ($self, $self->{'x1'}, $self->{'y1'}, $x, $y);
  return 0; # propagate event
}

# 'size-allocate' signal on the widget.
#
# The effect here is to re-constrain the x1,y1 position, in case it's now
# outside the allocated area, and to recheck the pointer position at x2,y2
# in case it's now outside, or now back inside, the allocated area
#
# x1,y1 is not moved (only reconstrained), so if $widget moves then that
# x1,y1 stays at the same position relative to the widget top-left 0,0.
# There's probably other sensible things to do with it, like anchor to a
# different edge, or a proportion of the size, etc, but a widget move during
# a lasso should be rare, so as long as it doesn't catch fire it should be
# fine for now.
#
sub _do_size_allocate {
  my ($widget, $alloc, $ref_weak_self) = @_;
  my $self = $$ref_weak_self or return;
  # re-run allocation constraints
  _maybe_move ($self,
               $self->{'x1'}, $self->{'y1'},
               $widget->get_pointer);
}


sub _do_button_release {
  my ($widget, $event, $ref_weak_self) = @_;
  my $self = $$ref_weak_self or return;
  if ($event->button == $self->{'button'}) {
    $self->end ($event);
  }
  return 0; # propagate event
}

sub _maybe_move {
  my ($self, $x1,$y1, $x2,$y2) = @_;
  my $widget = $self->{'widget'};

  ($x1,$y1) = _widget_constrain_coords ($widget, $x1,$y1);
  ($x2,$y2) = _widget_constrain_coords ($widget, $x2,$y2);

  if (   $x1 == $self->{'x1'}
      && $y1 == $self->{'y1'}
      && $x2 == $self->{'x2'}
      && $y2 == $self->{'y2'}) {
    return;
  }

  if ($self->{'drawn'}) {
    if (DEBUG) { print "  undraw\n"; }
    _draw ($self);
  }
  $self->{'x1'} = $x1;
  $self->{'y1'} = $y1;
  $self->{'x2'} = $x2;
  $self->{'y2'} = $y2;
  _draw ($self);
  $self->signal_emit ('moved', $x1,$y1, $x2,$y2);
}

sub _undraw {
  my ($self) = @_;
}

sub _draw {
  my ($self, $clip_region) = @_;
  if (DEBUG) { print "   _draw  ",$clip_region||'noclip',"\n"; }
  my $widget = $self->{'widget'};

  my $win = $widget->Gtk2_Ex_Xor_window
    || return;  # possible undef when unrealized in destruction
  my ($off_x, $off_y) = ($win != $widget->window
                         ? $win->get_position : (0, 0));
  my $gc = ($self->{'gc'} ||= do {
    Gtk2::Ex::Xor::get_gc ($widget, $self->{'foreground'},
                           line_width => ($self->{'line_width'} || 0),
                           line_style => ($self->{'line_style'}
                                          || DEFAULT_LINE_STYLE));
  });

  if ($clip_region) { $gc->set_clip_region ($clip_region); }
  _draw_rectangle_corners ($win, $gc, 0,
                           $self->{'x1'} - $off_x, $self->{'y1'} - $off_y,
                           $self->{'x2'} - $off_x, $self->{'y2'} - $off_y);
  if ($clip_region) { $gc->set_clip_region (undef); }
  $self->{'drawn'} = 1;
}

sub swap_corners {
  my ($self) = @_;
  if (! $self->{'active'}) { return; }

  my $x1 = $self->{'x1'};
  my $y1 = $self->{'y1'};
  _maybe_move ($self,
               $self->{'x2'}, $self->{'y2'},
               $self->{'x1'}, $self->{'y1'});
  _widget_warp_pointer ($self->{'widget'}, $x1, $y1);
}


# key snooper callback
sub _do_key_snooper {
  my ($target_widget, $event, $ref_weak_self) = @_;
  my $self = $$ref_weak_self or return 1; # propagate event

  # ignore key releases
  $event->type eq 'key-press' or return 0; # propagate event

  if (DEBUG) { print "Lasso key ", $event->keyval, "\n"; }

  if ($event->keyval == Gtk2::Gdk->keyval_from_name('Escape')) {
    $self->abort;
    return 1; # don't propagate

  } elsif ($event->keyval == Gtk2::Gdk->keyval_from_name('space')) {
    $self->swap_corners;
    return 1; # don't propagate

  } elsif ($event->keyval == Gtk2::Gdk->keyval_from_name('Return')) {
    $self->end ($event);
    return 1; # don't propagate
  }

  return 0; # propagate event
}

sub _do_grab_broken {
  my ($widget, $event, $ref_weak_self) = @_;
  my $self = $$ref_weak_self or return;
  if (DEBUG) { print "Lasso grab broken\n"; }

  $self->{'grabbed'} = 0;

  # if lassoing with a button drag then a break of the implicit grab almost
  # certainly means something else is now happening and lassoing should stop
  #
  # if lassoing from a non-button start then a break of our explicit grab
  # also almost certain means something else is happening and lassoing
  # should stop
  #
  # abort() doesn't use $event for anything, since the grab is already gone,
  # but pass it for the sake of completeness
  #
  $self->abort ($self, $event);

  return 0; # propagate
}

#------------------------------------------------------------------------------
# generic helpers

# Draw an outlined rectangle with corners at $x1,$y1 and $x2,$y2.
sub _draw_rectangle_corners {
  my ($drawable, $gc, $filled, $x1,$y1, $x2,$y2) = @_;
  if (DEBUG >= 2) { print "  draw rect $x1,$y1 - $x2,$y2\n"; }
  $drawable->draw_rectangle ($gc, $filled,
                             min ($x1, $x2), min ($y1, $y2),
                             abs ($x1 - $x2) + ($filled ? 1 : 0),
                             abs ($y1 - $y2) + ($filled ? 1 : 0));
}

sub _widget_constrain_coords {
  my ($widget, $x, $y) = @_;
  my $alloc = $widget->allocation;
  return (max (0, min ($alloc->width-1,  $x)),
          max (0, min ($alloc->height-1, $y)));
}

# $window->get_size is the most recent configure-event report, it doesn't
# make a server round-trip
sub _window_constrain_coords {
  my ($window, $x, $y) = @_;
  my ($width, $height) = $window->get_size;
  return (max (0, min ($width-1,  $x)),
          max (0, min ($height-1, $y)));
}

# Warp the mouse pointer to ($x,$y) in $widget coordinates.
#
sub _widget_warp_pointer {
  my ($widget, $x, $y) = @_;
  my $window = $widget->window
    or croak "Cannot warp mouse pointer on unrealized $widget";

  if ($widget->flags & 'no-window') {
    my $alloc = $widget->allocation;
    $x += $alloc->x;
    $y += $alloc->y;
  }
  my ($wx, $wy) = _window_get_root_position ($window);
  $window->get_display->warp_pointer ($window->get_screen, $x+$wx, $y+$wy);
}

# Return two values ($x,$y) which is the position of $window in root window
# coordinates.  This uses gdk_window_get_position() and so takes the most
# recent configure notify positions, as opposed to $window->get_origin which
# gets the latest with an X server round-trip (XTranslateCoordinates()).
#
# The loop here is similar to what gtk_widget_translate_coordinates() does
# chasing up through window ancestors.
#
sub _window_get_root_position {
  my ($window) = @_;
  my $x = 0;
  my $y = 0;
  while ($window->get_window_type ne 'root') {
    my ($parent_x, $parent_y) = $window->get_position;
    $x += $parent_x;
    $y += $parent_y;
    $window = $window->get_parent
      or croak '_window_get_root_position(): oops, didn\'t reach root window';
  }
  return ($x, $y);
}

# Return a server timestamp from $event, if it's not undef and if it's an
# event which has a timestamp.
sub _event_time {
  my ($event) = @_;
  if (Scalar::Util::blessed($event) && $event->can('time')) {
    return $event->time;
  } else {
    return GDK_CURRENT_TIME;
  }
}


1;
__END__

=head1 NAME

Gtk2::Ex::Lasso -- drag the mouse to lasso a rectangular region

=head1 SYNOPSIS

 use Gtk2::Ex::Lasso;
 my $lasso = Gtk2::Ex::Lasso->new (widget => $widget);
 $lasso->signal_connect (ended => sub { ... });
 $lasso->start ($event);

=head1 OBJECT HIERARCHY

C<Gtk2::Ex::Lasso> is a subclass of C<Glib::Object>.

    Glib::Object
      Gtk2::Ex::Lasso

=head1 DESCRIPTION

A C<Gtk2::Ex::Lasso> object implements a "lasso" style user selection of a
rectangular region in a widget window, drawing dashed lines as visual
feedback while selecting.

        +-------------------------+
        |                         |
        |   +-----------+         |
        |   |           |         |
        |   |           |         |
        |   +-----------*         |
        |                \mouse   |
        |                         |
        |                         |
        +-------------------------+

The lasso is activated by the C<start> function (see L</FUNCTIONS>).  You
setup your button press or keypress code to call that.  When started from a
button the lasso is active while the button is held down, ie. a drag.  This
is the usual way, but you can also begin from a keypress, or even something
strange like a menu entry.

The following keys are recognised while lassoing,

    Return      end selection
    Esc         abort the selection
    Space       swap the mouse pointer to the opposite corner

Other keys are propagated to normal processing.  The space to "swap" is
designed to let you move the opposite corner if you didn't start at the
right spot, or change your mind.

=head1 FUNCTIONS

=over 4

=item C<< Gtk2::Ex::Lasso->new (key => value, ...) >>

Create and return a new Lasso object.  Optional key/value pairs set initial
properties as per C<< Glib::Object->new >>.  Eg.

    my $ch = Gtk2::Ex::Lasso->new (widget => $widget);

=item C<< $lasso->start () >>

=item C<< $lasso->start ($event) >>

Start a lasso selection on C<$lasso>.  If C<$event> is a
C<Gtk2::Gdk::Event::Button> then releasing that button ends the selection.
For other event types or for C<undef> or omitted the selection ends only
with the Return key or an C<end> call.

=item C<< $lasso->end () >>

=item C<< $lasso->end ($event) >>

End the C<$lasso> selection and emit the C<ended> signal, or if C<$lasso> is
already inactive then do nothing.  This is the user Return key or button
release.

If you end a lasso in response to a button release, another button press, a
motion notify, or similar, then pass the C<Gtk2::Gdk::Event> as the optional
C<$event> parameter.  C<end> will use it for a final X,Y position, and for a
server timestamp if ungrabbing.  This can be important if event processing
is a bit lagged.

=item C<< $lasso->abort () >>

Abort the C<$lasso> selection and emit the C<aborted> signal, or if
C<$lasso> is already inactive then do nothing.  This is the user Esc key.

=item C<< $lasso->swap_corners() >>

Swap the mouse pointer to the opposite corner of the selection, by a "warp"
of the pointer (ie. a forcible movement).  This is the user Space key.

=back

=head1 PROPERTIES

=over 4

=item C<widget> (a C<Gtk2::Widget>, or C<undef>)

The target widget to act on.

=item C<active> (boolean, default false)

True while lasso selection is in progress.  Turning this on or off is the
same as calling C<start> or C<end> above (except you can't pass events).

=item C<foreground> (scalar, default C<undef>)

The foreground colour to draw the lasso.  This can be a string name (or
hexadecimal RGB), a C<Gtk2::Gdk::Color> object with an allocated pixel
value, or C<undef> for the widget's C<Gtk2::Style> foreground.

=item C<cursor> (scalar, default C<"hand1">)

The mouse cursor type to display while lassoing.  This can be any string or
object understood by C<Gtk2::Ex::WidgetCursor>, or C<undef> for no cursor
change.

A cursor change is highly desirable because when starting a lasso it's
normally too small for the user to see and so really needs another visual
indication that selection has begun.

=back

=head1 SIGNALS

=over 4

=item C<moved>, parameters: lasso, x1, y1, x2, y2, userdata

Emitted whenever the in-progress selected region changes (but not when it
ends).  x2,y2 is the corner with the mouse.

=item C<ended>, parameters: lasso, x1, y1, x2, y2, userdata

Emitted when a selection is complete and accepted by the user (as opposed to
aborted).  x2,y2 is the corner where the mouse finished (though it's unusual
to care which is which).

=item C<aborted>, parameters: lasso, userdata

Emitted when a region selection ends by the user wanting to abort, meaning
basically wanting no action on the region.

=back

=head1 OTHER NOTES

The lasso is drawn with an XOR between the requested foreground and a
background established by C<Gtk2::Ex::Xor>.  This is fast and portable but
only really suitable for a widget with a single dominant background pixel.

Expose events during lasso selection work, though they assume the target
widget's expose redraws only the expose event region given, as opposed to
doing a full window redraw.  Clipping the redraw is usual, and indeed
desirable.

Keypresses are obtained from the Gtk "snooper" mechanism, so they work even
if the lasso target widget doesn't have the focus, including when it's a
no-focus widget.  Keys not for the lasso are propagated in the usual way.

When the lasso is started from a keypress etc, not a button drag, an
explicit pointer grab is used so motion outside the widget window can be
seen.  In the current code a further C<start> call with a button press event
will switch to drag mode, so the corresponding release has the expected
effect.  But maybe that's a bit obscure, so perhaps in the future the way
this works will change.

=head1 BUGS

Changing the C<widget> property works, but doing so while the lasso is
active is unlikely to be good for the user.

=head1 SEE ALSO

L<Gtk2::Ex::CrossHair>, L<Glib::Object>, L<Gtk2::Ex::WidgetCursor>,

=head1 HOME PAGE

L<http://www.geocities.com/user42_kevin/gtk2-ex-xor/index.html>

=head1 LICENSE

Copyright 2007, 2008 Kevin Ryde

Gtk2-Ex-Xor is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free
Software Foundation; either version 3, or (at your option) any later
version.

Gtk2-Ex-Xor is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
more details.

You should have received a copy of the GNU General Public License along with
Gtk2-Ex-Xor.  If not, see L<http://www.gnu.org/licenses/>.

=cut
