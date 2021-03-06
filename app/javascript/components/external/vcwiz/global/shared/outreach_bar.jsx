import React from 'react';
import {getDomain, isLoggedIn} from '../utils';
import {TargetInvestorCategories, OutreachPath, CCEmail} from '../constants.js.erb'
import Store from '../store';
import {Button, Colors} from 'react-foundation';
import classNames from 'classnames';
import moment from 'moment';
import inflection from 'inflection';

const CategoryColors = {
  wishlist: '#2472DF',
  in_talks: '#2472DF',
  pitching: '#2472DF',
  passed: '#797C82',
  committed: '#3EAB1B',
};

export default class OutreachBar extends React.Component {
  state = {
    founder: Store.get('founder', {}),
  };

  componentWillMount() {
    this.subscription = Store.subscribe('founder', founder => this.setState({founder}));
  }

  componentWillUnmount() {
    Store.unsubscribe(this.subscription);
  }

  onClick = () => {
    window.location.href = OutreachPath;
  };

  renderEvent = ({action, arg1, arg2, first_name, last_name, firm_name, meta}) => {
    const name = `${first_name} ${last_name} from ${firm_name}`;
    const email = meta.email_subject ?  `email (${meta.email_subject})` : 'email';
    switch (action) {
      case 'investor_opened':
        return <span><b>{name} opened your {arg1 ? 'intro' : email}.</b> Look forward to a response soon!</span>;
      case 'investor_replied':
        return <span><b>{name} replied to your {arg1 ? 'intro' : email}.</b> Make sure you follow up!</span>;
      case 'investor_clicked':
        return <span><b>{name} clicked your link to <a href={arg2} target="_blank">{getDomain(arg2)}</a>.</b> I'm sure they were impressed!</span>;
      case 'intro_requested':
        return <span><b>you requested an intro to {name}.</b></span>;
      default:
        return null;
    }
  };

  renderReminder() {
    if (this.state.founder['scanner_enabled?']) {
      return;
    }
    const { stats, conversations } = this.state.founder;
    if ((_.isEmpty(stats) || !stats.emails)) {
      return (
        <span>
          { conversations.total ? "You haven't sent any emails yet! " : null }
          When you're ready, you can CC (or BCC) <b>{CCEmail}</b> in your investor emails to track your investor outreach.
          VCWiz will automatically update your conversation progress.
          Don't worry&mdash;VCWiz doesn't read the content of your e-mails.
        </span>
      );
    }
    return (
      <span>
        Remember to include <b>{CCEmail}</b> in your emails so we can help analyze your outreach!
      </span>
    );
  }

  renderStats() {
    const { stats } = this.state.founder;
    if (_.isEmpty(stats) || !stats.emails) {
      return null;
    }
    const { response_time, emails, investors } = stats;
    if (!response_time) {
      return <span>So far, you've sent <b>{emails} emails</b>, to over <b>{investors} investors</b>.</span>
    } else {
      return (
        <span>
          So far, you've sent <b>{emails} emails</b> to over <b>{investors} investors</b> and have an average response time of <b>{moment.duration(stats.response_time, 'seconds').humanize()}</b>.
        </span>
      );
    }
  }

  renderEvents() {
    const { events_with_meta } = this.state.founder;
    if (!events_with_meta || !events_with_meta.length) {
      return null;
    }
    return (
      <div className="events">
        Recently, {this.renderEvent(_.sample(events_with_meta))}
      </div>
    )
  }

  renderBusy() {
    const { conversations, stats } = this.state.founder;
    if (conversations.total) {
      if ((_.isEmpty(stats) || !stats.emails)) {
        return null;
      }
      return "You've been busy!";
    } else {
      return "Looks like you haven't picked out any investors to reach out to. Browse for some investors below!";
    }
  }

  renderStatsAndEvents() {
    return (
      <div>
        {this.renderBusy()}
        {' '}
        {this.renderStats()}
        {' '}
        {this.renderReminder()}
        {' '}
        {this.renderEvents()}
      </div>
    )
  }

  renderConversation(key) {
    const { conversations } = this.state.founder;
    const firms = _.uniq(conversations.recents[key] || []);
    const show = _.map(_.take(firms, 4), (f, i) => <div key={i}>{f}</div>);
    const left = firms.length - show.length;
    return (
      <div className={classNames('conversation-group', {'faded': !show.length})} key={key}>
        <div className="conversation-group-head" style={{backgroundColor: CategoryColors[key]}}>
          {inflection.titleize(key)} ({firms.length})
        </div>
        <div className="conversation-group-body">
          {show}
          {left ? `+ ${left} more` : null}
          {!show.length ? 'None yet!' : null}
        </div>
      </div>
    );
  }

  renderConversations() {
    return [
      this.renderConversation('wishlist'),
      this.renderConversation('in_talks'),
      this.renderConversation('pitching'),
      <hr key="vr" className="vr" />,
      this.renderConversation('passed'),
      this.renderConversation('committed'),
    ];
  }

  renderButton() {
    return (
      <div className="button-wrapper">
        <Button color={Colors.SECONDARY} onClick={this.onClick}>
          View Conversations
        </Button>
      </div>
    )
  }

  renderWelcome() {
    const { conversations } = this.state.founder;
    if (conversations.total) {
      return `You're in talks with ${conversations.total} investors.`;
    } else {
      return "You're not tracking any investors yet!"
    }
  }

  render() {
    if (!isLoggedIn()) {
      return null;
    }
    return (
      <div className="outreach-bar">
        <h4>
          Hi {this.state.founder.first_name}.
          {' '}
          {this.renderWelcome()}
        </h4>
        <div className="stats-and-events">{this.renderStatsAndEvents()}</div>
        <div className="conversations">{this.renderConversations()}</div>
        {this.renderButton()}
      </div>
    );
  }
}