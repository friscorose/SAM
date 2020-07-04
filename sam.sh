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

sam ()
{
  sam_init_agent () 
  {
    [ -n "$SAM_DEBUG" ] && echo "Initializing new ssh-agent";
    eval "$(ssh-agent -k &> /dev/null)";
    killall ssh-agent 2>/dev/null;
    /bin/rm -f $SAM_AUTH_SOCK
    [ -n "$SAM_DEBUG" ] && echo "SAM_AUTH_SOCK=$SAM_AUTH_SOCK"
    eval "$(ssh-agent -a $SAM_AUTH_SOCK -s | tee $SAM_ENV_FILE)";
  }
  sam_source_env () 
  {
    [ -n "$SAM_DEBUG" ] && echo "Sourcing $SAM_ENV_FILE"
    if [ -e "$SAM_ENV_FILE" ]; then
      source $SAM_ENV_FILE >/dev/null;
    fi
  }
  echo_sam () {
    [ -n "$SAM_DEBUG" ] && echo "calling echo_sam"
    if [ "$SSH_AUTH_SOCK" = "$SAM_AUTH_SOCK" ]; then
      echo "SAM($SSH_AGENT_PID) identities validated from localhost:";
    else
      echo "SAM identities validated from ${SSH_CONNECTION%%' '*}:";
    fi
    ssh-add -l &>/dev/null;
  }
  bye_sam () 
  {
    [ -n "$SAM_DEBUG" ] && echo "calling bye_sam"
    unset SAM_DEBUG;
    #unset SAM_ENV_PASS;
    #unset SAM_ENV_BASE;
    unset SAM_ENV_FILE; 
    unset SAM_AUTH_SOCK;
    #unset SSH_ASKPASS;
    unset SAM_CONFIRM;
    unset SAM_DISPLAY;
  }
  #env variables
  #export SAM_DEBUG="YES";
  [ -n "$SAM_DEBUG" ] && echo "Paging Sam!";
  #export SAM_ENV_PASS=$HOME/.ssh/.sam_env_pass;
  #export SAM_ENV_BASE=$HOME/.ssh/.sam_env_base;
  export SAM_ENV_FILE=$HOME/.ssh/.sam_env_file;
  export SAM_AUTH_SOCK=$HOME/.ssh/.sam_auth_sock;
  [ -n "$SAM_DEBUG" ] && echo "SAM_AUTH_SOCK=$SAM_AUTH_SOCK"
  if [ -x "$(command -v ssh-askpass)" ] && [ "$DISPLAY" ]; then
    export SSH_ASKPASS=`which ssh-askpass 2>/dev/null`
  fi
  export SAM_CONFIRM=${SSH_ASKPASS:+'-c'};

  local SAM_INIT_FLAG;
  local SAM_SOURCE_FLAG;

  SAM_INIT_FLAG="_SAM_INIT_"
  SAM_SOURCE_FLAG="_SAM_SOURCE_"
  SAM_INIT=false
  SAM_SOURCE=false

  local INPUT_KEYS;
  INPUT_KEYS=""
  for input in "$@"; do
    if [ "$input" == "$SAM_INIT_FLAG" ]; then 
      SAM_INIT=true
    elif [ "$input" == "$SAM_SOURCE_FLAG" ]; then
      SAM_SOURCE=true
    else
      INPUT_KEYS=${INPUT_KEYS:+"$INPUT_KEYS "}$input
    fi
  done

  [ "$SAM_INIT" == true ] && sam_init_agent
  [ "$SAM_SOURCE" == true ] && sam_source_env && bye_sam && return #this conditional exits

  #From ssh-add man-page
  # -l      Lists fingerprints of all identities currently represented by the agent.
  # Exit status is:   0 ssh-agent is reachable and has at least one key.
  #                   1 ssh-agent is reachable and has no keys
  #                   2 ssh-add is unable to contact the authentication agent.
  local SA_Stat;
  ssh-add -l &> /dev/null; SA_Stat=$?;
  if [ $SA_Stat -eq 2 ]; then
    #No agent in env, try stored agent
    [ -n "$SAM_DEBUG" ] && echo "Using stored agent, is it viable?";
    sam_source_env
    ssh-add -l &> /dev/null; SA_Stat=$?;
  else
    [ -n "$SAM_DEBUG" ] && echo "agent from env is available.";
  fi

  [ -n "$SAM_DEBUG" ] && echo -n "SAM branching on condition: $SA_Stat, ";
  case $SA_Stat in
    2)  [ -n "$SAM_DEBUG" ] && echo "agent unreachable, start a new one.";
      sam_init_agent
      ;&
  esac

  [ -n "$SAM_DEBUG" ] && echo "Check/add keys to agent.";
  SAM_KEYS=$(ssh-add -l);
  local KEYS;
  KEYS=""
  for key in "$INPUT_KEYS"; do
    [ "${SAM_KEYS#*$key}" != "$SAM_KEYS" ] && echo "$key already added" && continue
    KEYS=${KEYS:+"$KEYS "}$key
  done
  if [ -n "$KEYS" ]; then
    for n in {1..3}; do
      [ -n "$SAM_DEBUG" ] && echo "ssh-add $SAM_CONFIRM $KEYS" 
      ssh-add $SAM_CONFIRM $KEYS && break;
      [ -n "$SAM_DEBUG" ] && echo "Adding key failed, please try again."
    done;
  fi
  echo_sam;
  bye_sam;
}
