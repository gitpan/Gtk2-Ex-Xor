#!/usr/bin/perl

# Copyright 2008 Kevin Ryde

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


use strict;
use warnings;
use Gtk2 '-init';
use Gtk2::Ex::CrossHair;
use Data::Dumper;

use File::Basename;
my $progname = basename($0);

my $toplevel = Gtk2::Window->new('toplevel');
$toplevel->signal_connect (destroy => sub { Gtk2->main_quit });

my $hbox = Gtk2::HBox->new (0, 0);
$toplevel->add ($hbox);

my $frame = Gtk2::Frame->new;
$hbox->pack_start ($frame, 0,0,0);

my $vbox1 = Gtk2::VBox->new (0, 0);
$frame->add ($vbox1);

my $vbox = Gtk2::VBox->new (0, 0);
$hbox->pack_start ($vbox, 1,1,0);

my $area1_width = 400;
my $area1_height = 200;

my $layout = Gtk2::Layout->new;
$layout->set_size_request ($area1_width+20, $area1_height+20);
$vbox->pack_start ($layout, 1, 1, 0);

my $area1 = Gtk2::DrawingArea->new;
$area1->modify_fg ('normal', Gtk2::Gdk::Color->parse ('white'));
$area1->modify_bg ('normal', Gtk2::Gdk::Color->parse ('black'));
$area1->set_name ('one');
$area1->set_size_request (400, 200);
$area1->set_flags ('can-focus');
$area1->grab_focus;
$layout->add ($area1);

{
  my $label = Gtk2::Label->new (" xxx ");
  $vbox->add ($label);
}

my $area2 = Gtk2::DrawingArea->new;
$area2->set_name ('two');
$area2->set_size_request (400, 200);
$area2->set_flags ('can-focus');
$vbox->add ($area2);

{
  my $label = Gtk2::Label->new (" xxx ");
  $vbox->add ($label);
}

my $label = Gtk2::Label->new
  ('fjksdjf kds jfksd jfksd jfk sdjkf sjdkf jsdk fjksd fjksd
fdsjkf jsdkf jksd fjksd fjksd fkjds fjk dskjf skd
fjksdf jsdkf jksd fjksd fjksd fjksd fjskd fjksd fjksd
');
my $eventbox = Gtk2::EventBox->new;
$eventbox->add ($label);
$vbox->pack_start ($eventbox, 1,1,0);

{
  my $label = Gtk2::Label->new (" xxx ");
  $vbox->add ($label);
}

my $entry = Gtk2::Entry->new;
$area2->set_name ('four');
$vbox->add ($entry);


my $cross = Gtk2::Ex::CrossHair->new
  (widgets => [ $area1, $area2, $eventbox, $entry ],
   foreground => 'orange',
  );
$cross->signal_connect (notify => sub {
                          my ($toplevel, $pspec, $self) = @_;
                          print "$progname: notify '",$pspec->get_name,"'\n";
                        });

$area1->add_events (['button-press-mask','key-press-mask']);
$area1->signal_connect
  (button_press_event =>
   sub {
     my ($widget, $event) = @_;
     print "$progname: start button, widget ",$widget->get_name,"\n";
     $cross->start ($event);
     print "$progname: widget window events ",$widget->window->get_events,"\n";
     return 0; # propagate
   });
$area1->signal_connect
  (key_press_event =>
   sub {
     my ($widget, $event) = @_;
     if ($event->keyval == Gtk2::Gdk->keyval_from_name('c')) {
       print "$progname: start key $widget\n";
       $cross->start ($event);
       return 1; # don't propagate
     } elsif ($event->keyval == Gtk2::Gdk->keyval_from_name('e')) {
       my ($width, $height) = $area1->window->get_size;
       print "$progname: queue draw top left quarter\n";
       $area1->queue_draw_area (0,0, $width/2, $height/2);
       return 1; # don't propagate
     } else {
       return 0; # propagate
     }
   });

{
  my $button = Gtk2::Button->new_with_label ('Start');
  $vbox1->pack_start ($button, 0,0,0);
  $button->signal_connect
    (clicked => sub {
       print "$progname: start\n";
       $cross->start;
     });
}
{
  my $button = Gtk2::Button->new_with_label ('End');
  $vbox1->pack_start ($button, 0,0,0);
  $button->signal_connect
    (clicked => sub {
       print "$progname: end\n";
       $cross->end;
     });
}
{
  my $button = Gtk2::CheckButton->new_with_label ('Active');
  $vbox1->pack_start ($button, 0,0,0);
  $cross->signal_connect ('notify::active' => sub {
                            my $active = $cross->get ('active');
                            print "$progname: cross notify active $active\n";
                            $button->set_active ($active);
                          });
  $button->signal_connect
    (toggled => sub {
       my $active = $button->get_active;
       print "$progname: hint toggled $active\n";
       $cross->set (active => $active);
     });
}
{
  my $button = Gtk2::CheckButton->new_with_label ('Hint Mask');
  $vbox1->pack_start ($button, 0,0,0);
  $button->signal_connect
    (toggled => sub {
       print "$progname: hint toggled\n";

       my $window = $area1->window;
       my $events = $window->get_events;
       if ($button->get_active) {
         $events = $events + 'pointer-motion-hint-mask';
       } else {
         $events = $events - 'pointer-motion-hint-mask';
       }
       $window->set_events ($events);
       
       my ($width, $height) = $area1->window->get_size;
       print "$progname: area1 ${width}x${height} window events ",
         $area1->window->get_events,"\n";
     });
}
{
  my $adj = Gtk2::Adjustment->new (3, 0, 99, 1, 10, 10);
  $cross->set ('line-width' => $adj->value);
  my $spin = Gtk2::SpinButton->new ($adj, 1, 0);
  $vbox1->pack_start ($spin, 0,0,0);
  $spin->signal_connect (value_changed => sub {
                           my $value = $spin->get_value;
                           print "$progname: cross line width $value\n";
                           $cross->set ('line-width' => $value);
                         });
}
{
  my $button = Gtk2::CheckButton->new_with_label ('DebugUps');
  $button->set_tooltip_markup
    ("Set Gtk2::Gdk::Window->set_debug_updates to flash invalidated regions");
  $button->set_active (0);
  $button->signal_connect (toggled => sub {
                             Gtk2::Gdk::Window->set_debug_updates
                                 ($button->get_active);
                           });
  $vbox1->pack_start ($button, 0,0,0);
}
{
  my $timer_id;
  my $idx = 0;
  my @widths = (400, 350, 300, 350);
  my $button = Gtk2::CheckButton->new_with_label ('Resizing');
  $button->set_tooltip_markup
    ("Check this to resize the DrawingArea under a timer, to test lasso recalc when some of it goes outside the new size");
  $vbox1->pack_start ($button, 0,0,0);
  $button->signal_connect ('toggled' => sub {
                             if ($button->get_active) {
                               $timer_id ||= do {
                                 print "$progname: resizing start\n";
                                 Glib::Timeout->add (1000, \&resizing_timer);
                               };
                             } else {
                               if ($timer_id) {
                                 print "$progname: resizing stop\n";
                                 Glib::Source->remove ($timer_id);
                                 $timer_id = undef;
                               }
                             }
                           });
  sub resizing_timer {
    $idx++;
    if ($idx >= @widths) {
      $idx = 0;
    }
    my $width = $widths[$idx];
    print "$progname: resize to $width,$area1_height\n";
    $area1->set_size_request ($width, $area1_height);
    return 1; # keep running
  }
}
{
  my $timer_id;
  my $idx = 0;
  my @x = (0, 50, 100, 50);
  my $button = Gtk2::CheckButton->new_with_label ('Repositioning');
  $button->set_tooltip_markup
    ("Check this to resize the DrawingArea under a timer, to test lasso recalc when some of it goes outside the new size");
  $vbox1->pack_start ($button, 0,0,0);
  $button->signal_connect ('toggled' => sub {
                             if ($button->get_active) {
                               $timer_id ||= do {
                                 print "$progname: repositioning start\n";
                                 Glib::Timeout->add (1000, \&repositioning_timer);
                               };
                             } else {
                               if ($timer_id) {
                                 print "$progname: repositioning stop\n";
                                 Glib::Source->remove ($timer_id);
                                 $timer_id = undef;
                               }
                             }
                           });
  sub repositioning_timer {
    $idx++;
    if ($idx >= @x) {
      $idx = 0;
    }
    my $x = $x[$idx];
    print "$progname: reposition to $x,0\n";
    $layout->move ($area1, $x, 0);
    return 1; # keep running
  }
}
{
  my $timer_id;
  my $idx = 0;
  my @backgrounds = ('red', 'black', 'green', 'blue', 'grey');
  my $button = Gtk2::CheckButton->new_with_label ('Background Changing');
  $button->set_tooltip_markup
    ("Check this to update the background in the widget, to see the lasso gc follow it");
  $vbox1->pack_start ($button, 0,0,0);
  $button->signal_connect ('toggled' => sub {
                             if ($button->get_active) {
                               $timer_id ||= do {
                                 print "$progname: background changing start\n";
                                 Glib::Timeout->add (2000, \&background_timer);
                               };
                             } else {
                               if ($timer_id) {
                                 print "$progname: background changing stop\n";
                                 Glib::Source->remove ($timer_id);
                                 $timer_id = undef;
                               }
                             }
                           });
  sub background_timer {
    $idx++;
    if ($idx >= @backgrounds) {
      $idx = 0;
    }
    my $color = Gtk2::Gdk::Color->parse ($backgrounds[$idx]);
    $area1->modify_bg ('normal', $color);
    $color = Gtk2::Gdk::Color->parse ($backgrounds[-$idx]);
    $area2->modify_bg ('normal', $color);
    return 1; # keep running
  }
}

$toplevel->show_all;
Gtk2->main;
