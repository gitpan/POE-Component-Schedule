package POE::Component::Schedule;

use 5.008;

our $VERSION = '0.03';

use strict;
use warnings;

use POE;

my $Singleton;
my $ID_Sequence = 'a';    # sequence is 'a', 'b', ..., 'z', 'aa', 'ab', ...
my %Schedule_Ticket;      # Hash helps remember alarm id for cancel.

#
# crank up the schedule session
#
sub spawn {
    my $class = shift;
    my %arg   = @_;

    if ( !defined $Singleton ) {

        $Singleton = POE::Session->create(
            inline_states => {
                _start => sub {
                    my ($k) = $_[KERNEL];

                    $k->alias_set( $arg{'Alias'} || $class );
                    $k->sig( 'SHUTDOWN', 'shutdown' );
                },

                schedule     => \&_schedule,
                client_event => \&_client_event,
                cancel       => \&_cancel,

                shutdown => sub {
                    #print "# $class shutdown\n";
                    my $k = $_[KERNEL];

                    # FIXME We are removing too much here!
                    $k->alarm_remove_all();

                    $k->sig_handled();
                },
                _stop => sub {
                    #print "# $class _stop\n";
                    $Singleton = undef;
                },
            },
        )->ID;
    }
}

#
# schedule the next event
#  ARG0 is a client session,
#  ARG1 is the client event name,
#  ARG2 is a DateTime::Set iterator
#  ARG3 is an schedule ticket
#  ARG4 .. $#_ are arguments to the client event
#
sub _schedule {
    my ( $k, $s, $e, $ds, $tix, @arg ) = @_[ KERNEL, ARG0 .. $#_ ];
    my $n;

    #
    # deal with DateTime::Sets that are finite
    #
    return 1 unless ( $n = $ds->next );

    $Schedule_Ticket{$tix} =
      $k->alarm_set( 'client_event', $n->epoch, $s, $e, $ds, $tix, @arg );
}

#
# handle a client event and schedule the next one
#  ARG0 is a client session,
#  ARG1 is the client event name,
#  ARG2 is a DateTime::Set iterator
#  ARG3 is an schedule ticket
#  ARG4 .. $#_ are arguments to the client event
#
sub _client_event {
    my ( $k, $s, $e, $ds, $tix, @arg ) = @_[ KERNEL, ARG0 .. $#_ ];

    $k->post( $s, $e, @arg );
    _schedule(@_);
}

#
# cancel an alarm
#
sub _cancel {
    my ( $k, $id ) = @_[ KERNEL, ARG0 ];

    $k->alarm_remove($id);
}

#
# takes a POE::Session, an event name and a DateTime::Set
#
sub add {

    my $class  = shift;
    my $ticket = $ID_Sequence++;    # get the next ticket;

    my ( $session, $event, $iterator, @args ) = @_;
    $iterator->isa('DateTime::Set')
      or die __PACKAGE__ . "->add: third arg must be a DateTime::Set";

    $class->spawn unless $Singleton;

    $poe_kernel->post( $poe_kernel->ID_id_to_session($Singleton),
        'schedule', $session, $event, $iterator, $ticket, @args, );
    $Schedule_Ticket{$ticket} = ();

    return bless \$ticket, ref $class || $class;
}

sub delete {
    my $self   = shift;
    my $ticket = $$self;

    $poe_kernel->post(
        $poe_kernel->ID_id_to_session($Singleton),
        'cancel', $Schedule_Ticket{$ticket},
    );
    delete $Schedule_Ticket{$ticket};
}

sub DESTROY {
    $_[0]->delete if exists $Schedule_Ticket{${$_[0]}};
}

{
    no warnings;
    *new = \&add;
}

1;
__END__

=head1 NAME

POE::Component::Schedule - Schedule POE events using DateTime::Set iterators

=head1 SYNOPSIS

    use POE qw(Component::Schedule);
    use DateTime::Set;

    $s1 = POE::Session->create(
        inline_states => {
            _start => sub {
                $_[HEAP]{sched} = POE::Component::Schedule->add(
                    $_[SESSION], Tick => DateTime::Set->from_recurrence(
                        after      => DateTime->now,
                        before     => DateTime->now->add(seconds => 3)
                        recurrence => sub {
                            return $_[0]->truncate( to => 'second' )->add( seconds => 1 )
                        },
                    ),
                );
            },
            Tick => sub {
                print 'tick ', scalar localtime, "\n";
            },
            remove_sched => sub {
                # Three ways to remove a schedule
                # The first one is only for API compatibility with POE::Component::Cron
                $_[HEAP]{sched}->delete;
                $_[HEAP]{sched} = undef;
                delete $_[HEAP]{sched};
            }
            _stop => sub {
                print "_stop\n";
            },
        },
    );

=head1 DESCRIPTION

This component encapsulates a session that sends events to client sessions
on a schedule as defined by a DateTime::Set iterator.

=head1 POE::Component::Schedule METHODS

=head2 spawn(Alias => I<name>)

No need to call this in normal use, add() and new() all crank
one of these up if it is needed. Start up a PoCo::Schedule. Returns a
handle that can then be added to.

=head2 add()

    my $sched = POE::Component::Schedule->add(
        $session_object,
        $event_name,
        $DateTime_Set_iterator,
        @event_args
    );

Add a set of events to the schedule. The C<$session_object> and C<$event_name> are passed
to POE without even checking to see if they are valid and so have the same
warnings as ->post() itself.
C<$session_object> must be a real L<POE::Session>, not a session ID. Else session
reference count will not be increased and the session may end before receiving all
events.

Returns a schedule handle. The event is removed from when the handle is not referenced
anymore.


=head2 new

new is an alias for add

=head1 SCHEDULE HANDLE METHODS

=head2 delete

Removes a schedule using the handle returned from ->add or ->new.

B<DEPRECATED>: Schedules are now automatically deleted when they are not
referenced anymore. So just setting the container variable to C<undef> will
delete the schedule.

=head1 SEE ALSO

L<POE>, L<DateTime::Set>, L<POE::Component::Cron>.

=head1 BUGS

You can look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=POE-Component-Schedule>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/POE-Component-Schedule>

=item * CPAN Ratings

L<http://cpanratings.perl.org/p/POE-Component-Schedule>

=item * Search CPAN

L<http://search.cpan.org/dist/POE-Component-Schedule/>

=back


=head1 ACKNOWLEDGMENT

This module is a friendly fork of POE::Component::Cron to extract the generic
parts and isolate the Cron specific code in order to reduce dependencies on
other CPAN modules.

The orignal author of POE::Component::Cron is Chris Fedde.

See L<https://rt.cpan.org/Ticket/Display.html?id=44442>

=head1 AUTHORS

=over 4

=item Olivier MenguE<eacute>, C<<< dolmen@cpan.org >>>

=item Chris Fedde, C<<< cfedde@cpan.org >>>

=back

=head1 COPYRIGHT AND LICENSE

=over 4

=item Copyright E<copy> 2007-2008 Chris Fedde

=item Copyright E<copy> 2009 Olivier MenguE<eacute>

=back

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.

=cut
