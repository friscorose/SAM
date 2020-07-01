# ssh agent manager (sam) typically sourced by .bashrc
# default ssh-agent? NO!
# xfconf-query -c xfce4-session -p /startup/ssh-agent/enabled -n -t bool -s false
# sed -i 's/^use-ssh-agent/#use-ssh-agent/' /etc/X11/Xsession.options
#
# Instructions for setting up an ssh certificate authority
#ref  $ elinks https://ef.gy/hardening-ssh -dump > ssh_ca_ref.txt

# Either SAM represents no agent, a local agent and the agent needs persistence or
# SAM represents a remote agent that will be transient.
# If the transient is viable, it needs priority and SAM will update environment.
# If transient is not viable, restore local agent environment.

sam_prep () 
{
  #export SAM_ENV_PASS=$HOME/.ssh/.sam_env_pass;
  #export SAM_ENV_BASE=$HOME/.ssh/.sam_env_base;
  export SAM_ENV_FILE=$HOME/.ssh/.sam_env_file;
  export SAM_AUTH_SOCK=$HOME/.ssh/.sam_auth_sock;
  if [ -x "$(command -v ssh-askpass)" ] && [ "$DISPLAY" ]; then
    export SSH_ASKPASS=`which ssh-askpass 2>/dev/null`
    #export SSH_ASKPASS=${SSH_ASKPASS-/usr/bin/ssh-askpass};
    SAM_CONFIRM=${SSH_ASKPASS:+'-c'};
  fi
  if [ -e $SAM_ENV_FILE ]; then
    source $SAM_ENV_FILE >/dev/null;
  fi
}

sam_init_agent () 
{
  eval "$(ssh-agent -k &> /dev/null)";
  killall ssh-agent 2>/dev/null;
  /bin/rm -f $SAM_AUTH_SOCK
  eval "$(ssh-agent -a $SAM_AUTH_SOCK -s | tee $SAM_ENV_FILE)";
}

sam () 
{ 
  #DEBUG="YES";
  [ "$DEBUG" ] && echo "Paging Sam!";

  sam_prep

  bye_sam () {
    if [ "$SSH_AUTH_SOCK" = "$SAM_AUTH_SOCK" ]; then
      echo "SAM($SSH_AGENT_PID) identities validated from localhost:";
    else
      echo "SAM identities validated from ${SSH_CONNECTION%%' '*}:";
    fi
    ssh-add -l;
    unset DEBUG; 
    unset SA_Stat; 
    unset SAM_ENV_FILE; 
    unset SAM_AUTH_SOCK;
    unset SAM_KEYS;
    unset SAM_CONFIRM;
    unset SAM_DISPLAY;
  }

  #From ssh-add man-page
  # -l      Lists fingerprints of all identities currently represented by the agent.
  # Exit status is:   0 ssh-agent is reachable and has at least one key.
  #                   1 ssh-agent is reachable and has no keys
  #                   2 ssh-add is unable to contact the authentication agent.
  ssh-add -l &> /dev/null; SA_Stat=$?;
  if [ $SA_Stat -eq 2 ]; then
    #No agent in env, try stored agent
    if [ -e $SAM_ENV_FILE ]; then
      [ -n "$DEBUG" ] && echo "Using stored agent, is it viable?";
      source $SAM_ENV_FILE;
      ssh-add -l &> /dev/null; SA_Stat=$?;
    fi
  else
    [ "$DEBUG" ] && echo "agent from env is available.";
  fi

  [ -n "$DEBUG" ] && echo -n "SAM branching on condition: $SA_Stat, ";
  case $SA_Stat in
    2)  [ "$DEBUG" ] && echo "agent unreachable, start a new one.";
      sam_init_agent
      ;&
    *)  [ "$DEBUG" ] && echo "Check/add keys to agent.";
  esac
  SAM_KEYS=$(ssh-add -l);
  KEYS=""
  for key in "$@"; do
    [ ! -f "$key" ] && echo "cannot find $key" && continue
    [ "${SAM_KEYS#*$key}" != "$SAM_KEYS" ] && echo "$key already added" && continue
    KEYS=${KEYS:+"$KEYS "}$key
    #if [ -z "$KEYS" ]; then
    #  KEYS="$key"
    #else
    #  KEYS="$KEYS $key"
    #fi
  done
  if [ -n "$KEYS" ]; then
    for n in {1..3}; do
      [ "$DEBUG" ] && echo "ssh-add $SAM_CONFIRM $KEYS" 
      ssh-add $SAM_CONFIRM $KEYS && break;
      [ "$DEBUG" ] && echo "Adding key failed, please try again."
    done;
  fi
  bye_sam;
}
