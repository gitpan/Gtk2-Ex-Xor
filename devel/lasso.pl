#!/usr/bin/perl

# Copyright 2008 Kevin Ryde

# This file is part of Gtk2-Ex-Xor.
#
# Gtk2-Ex-Xor is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 2, or (at your option) any later
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
use Gtk2::Ex::Lasso;
use Data::Dumper;

my $toplevel = Gtk2::Window->new('toplevel');
$toplevel->signal_connect (destroy => sub { Gtk2->main_quit; });

my $hbox = Gtk2::HBox->new;
$toplevel->add ($hbox);

my $vbox = Gtk2::VBox->new;
$hbox->pack_start ($vbox, 0, 0, 0);

my $area_width = 500;
my $area_height = 300;

my $layout = Gtk2::Layout->new;
$layout->set_size_request ($area_width+20, $area_height+20);
$hbox->pack_start ($layout, 1, 1, 0);

my $area = Gtk2::DrawingArea->new;
$area->set_size_request ($area_width, $area_height);
$area->modify_fg ('normal', Gtk2::Gdk::Color->parse ('white'));
$area->modify_bg ('normal', Gtk2::Gdk::Color->parse ('black'));
$layout->add ($area);

my $lasso = Gtk2::Ex::Lasso->new (widget => $area,
                                  # cursor => 'hand1'
                                 );
$area->signal_connect
  (key_press_event =>
   sub {
     my ($area, $event, $userdata) = @_;
     if ($event->keyval == Gtk2::Gdk->keyval_from_name('s')) {
       print __FILE__.": start key\n";
       $lasso->start ($event);
       return 1; # don't propagate
     } elsif ($event->keyval == Gtk2::Gdk->keyval_from_name('e')) {
       print __FILE__.": end\n";
       $lasso->end;
       return 1; # don't propagate
     } elsif ($event->keyval == Gtk2::Gdk->keyval_from_name('r')) {
       print __FILE__.": redraw\n";
       $area->queue_draw;
       return 1; # don't propagate
     }
     return 0; # propagate
   });
$area->add_events(['button-press-mask']);
$area->signal_connect (button_press_event =>
                       sub {
                         my ($area, $event, $userdata) = @_;
                         print __FILE__.": start button\n";
                         $lasso->start ($event);
                       });

$lasso->signal_connect (moved =>
                        sub {
                          print __FILE__.": moved ", join(' ',@_), "\n";
                        });
$lasso->signal_connect (aborted =>
                        sub {
                          print __FILE__.": aborted ", join(' ',@_), "\n";
                        });
$lasso->signal_connect (ended =>
                        sub {
                          print __FILE__.": ended ", join(' ',@_), "\n";
                        });

{
  my $button = Gtk2::CheckButton->new_with_label ('Active');
  $vbox->pack_start ($button, 0,0,0);
  $lasso->signal_connect ('notify::active' => sub {
                            my $active = $lasso->get ('active');
                            print __FILE__,": lasso notify active $active\n";
                            $button->set_active ($active);
                          });
  $button->signal_connect
    (toggled => sub {
       my $active = $button->get_active;
       print __FILE__,": hint toggled $active\n";
       $lasso->set (active => $active);
     });
}
{
  my $button = Gtk2::Button->new_with_label ('Start');
  $button->signal_connect (clicked => sub { $lasso->start; });
  $vbox->pack_start ($button, 0, 0, 0);
}
{
  my $button = Gtk2::Button->new_with_label ('End');
  $button->signal_connect (clicked => sub { $lasso->end; });
  $vbox->pack_start ($button, 0, 0, 0);
}
{
  my $button = Gtk2::Button->new_with_label ('Abort');
  $button->signal_connect (clicked => sub { $lasso->abort; });
  $vbox->pack_start ($button, 0, 0, 0);
}
{
  my $button = Gtk2::Button->new_with_label ('Swap');
  $button->signal_connect (clicked => sub { $lasso->swap_corners; });
  $vbox->pack_start ($button, 0, 0, 0);
}
{
  my $button = Gtk2::Button->new_with_label ('Redraw');
  $button->signal_connect (clicked => sub { $area->queue_draw; });
  $vbox->pack_start ($button, 0, 0, 0);
}
{
  my $button = Gtk2::Button->new_with_label ('Delayed Unmap');
  $button->set_tooltip_markup
    ("Click to unmap the DrawingArea widget after a delay of 2 seconds (use this to exercise grab_broken handling)");
  $button->signal_connect (clicked => sub {
                             Glib::Timeout->add (2000, # milliseconds
                                                 sub {
                                                   $area->unmap;
                                                   return 0; # stop
                                               });
                           });
  $vbox->pack_start ($button, 0, 0, 0);
}
{
  my $button = Gtk2::Button->new_with_label ('Delayed Iconify');
  $button->set_tooltip_markup
    ("Click to iconify the program after a delay of 2 seconds (use this to exercise grab_broken handling)");
  $button->signal_connect (clicked => sub {
                             Glib::Timeout->add (2000, # milliseconds
                                                 sub {
                                                   $toplevel->iconify;
                                                   return 0; # stop
                                               });
                           });
  $vbox->pack_start ($button, 0, 0, 0);
}
{
  my $combobox = Gtk2::ComboBox->new_text;
  $vbox->pack_start ($combobox, 0,0,0);
  $combobox->append_text ('invisible');
  $combobox->append_text ('undef');
  $combobox->append_text ('boat');
  $combobox->append_text ('umbrella');
  $combobox->append_text ('cross');
  $combobox->set_active (0);

  $combobox->signal_connect
    (changed => sub {
       my $type = $combobox->get_active_text;
       if ($type eq 'undef') { $type = undef; }
       $lasso->set (cursor => $type);
     });
}
{
  my $timer_id;
  my $idx = 0;
  my @widths = (500, 450, 400, 450);
  my $button = Gtk2::CheckButton->new_with_label ('Resizing');
  $button->set_tooltip_markup
    ("Check this to resize the DrawingArea under a timer, to test lasso recalc when some of it goes outside the new size");
  $vbox->pack_start ($button, 0,0,0);
  $button->signal_connect ('toggled' => sub {
                             if ($button->get_active) {
                               $timer_id ||= do {
                                 print __FILE__,": resizing start\n";
                                 Glib::Timeout->add (1000, \&resizing_timer);
                               };
                             } else {
                               if ($timer_id) {
                                 print __FILE__,": resizing stop\n";
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
    print __FILE__,": resize to $width,$area_height\n";
    $area->set_size_request ($width, $area_height);
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
  $vbox->pack_start ($button, 0,0,0);
  $button->signal_connect ('toggled' => sub {
                             if ($button->get_active) {
                               $timer_id ||= do {
                                 print __FILE__,": repositioning start\n";
                                 Glib::Timeout->add (1000, \&repositioning_timer);
                               };
                             } else {
                               if ($timer_id) {
                                 print __FILE__,": repositioning stop\n";
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
    print __FILE__,": reposition to $x,0\n";
    $layout->move ($area, $x, 0);
    return 1; # keep running
  }
}
$toplevel->show_all;
Gtk2->main;
