#!/bin/bash
if [ $# -eq 0 ]; then
  echo "Input number(integer) of MAVs as first argument"
  exit 1
fi

CUR_INPUT=$1
NUM_MAV=0
CSV_INPUT=false
let pos_cnt=0

if echo $CUR_INPUT | grep -Eq '^[+-]?[0-9]+$'; then
  NUM_MAV=$1
  echo "Running simulated $CUR_INPUT MAVs"
elif [[ $CUR_INPUT == *.csv ]]; then
  declare -a pos_val
  while read line
  do
    echo "Line is : $line"
    for i in $(echo $line | sed "s/,/ /g")
    do
        # call your procedure/other scripts here below
        #echo "$i"
        pos_val+=("$i")
    done
    NUM_MAV=$[${NUM_MAV} + 1]
  done < $CUR_INPUT
  CSV_INPUT=true
  # let pos_cnt=0
  # for id in $(seq 1 $NUM_MAV)
  # do
  #   echo ${pos_val[${pos_cnt}]} ${pos_val[$(expr ${pos_cnt} + 1)]}
  #   let pos_cnt+=3
  #   #echo $pos_cnt
  # done
else
  echo "Input number(integer) of MAVs or CSV with start_locations as first argument"
  exit 1
fi

if [ ${NUM_MAV} -eq 1 ]; then
  RQT_GUI=rqt_mav_manager
else
  RQT_GUI=rqt_multi_mav_gui
fi

# TODO parse this from command line? Possibly list of mav ids and namespace?
MAV_NAMESPACE=dragonfly

if [ $# -eq 2 ]; then
  MAV_NAMESPACE=$2
fi

MAV_TYPE=hummingbird
WORLD_FRAME_ID=simulator
echo "MAV napespace: $MAV_NAMESPACE MAV Type: $MAV_TYPE"

MASTER_URI=http://localhost:11311
SETUP_ROS_STRING="export ROS_MASTER_URI=${MASTER_URI}"
SESSION_NAME=demo_sim${NUM_MAV}

CURRENT_DISPLAY=${DISPLAY}
if [ -z ${DISPLAY} ];
then
  echo "DISPLAY is not set"
  CURRENT_DISPLAY=:0
fi

if [ -z ${TMUX} ];
then
  TMUX= tmux new-session -s $SESSION_NAME -d
  echo "Starting new session."
else
  echo "Already in tmux, leave it first."
  exit
fi

# Generate rviz config file for specific mav from default one
RVIZ_CONFIG_FILE="$HOME/.ros/wp_nav.rviz"
LAUNCH_PATH=$(rospack find kr_mav_launch)
cp $LAUNCH_PATH/launch/rviz_config.rviz ${RVIZ_CONFIG_FILE}
sed -i "s/simulator/${WORLD_FRAME_ID}/g" ${RVIZ_CONFIG_FILE}
sed -i "s/quadrotor\/waypoints/${MAV_NAMESPACE}1\/waypoints/g" ${RVIZ_CONFIG_FILE}
sed -i "s/quadrotor/temp/g" ${RVIZ_CONFIG_FILE}

# Generate multi_mav_manger yaml config file based on number of robots
cp $(rospack find kr_multi_mav_manager)/config/dragonfly/multi_mav_manager_single.yaml ~/.ros/multi_mav_manager.yaml
for id in $(seq 1 $NUM_MAV)
do
  MAV_NAME=${MAV_NAMESPACE}${id}
  sed -i "1a\  '"${MAV_NAME}"'," ~/.ros/multi_mav_manager.yaml
  echo "/${MAV_NAME}/active: true" >> ~/.ros/multi_mav_manager.yaml
done

round()
{
echo $(printf %.$2f $(echo "scale=$2;(((10^$2)*$1)+0.5)/(10^$2)" | bc))
};

n_rows=`echo "sqrt(${NUM_MAV})" | bc -l`
n_rows=$(round $n_rows 0)

div=$(( ${NUM_MAV} / ${n_rows} ))
n_cols=$(round  $div 0)
echo "Grid rows, cols: " $n_rows $n_cols
spacing=1

# Make mouse useful in copy mode
tmux setw -g mouse on

tmux rename-window -t $SESSION_NAME "Main"
tmux send-keys -t $SESSION_NAME "$SETUP_ROS_STRING; roscore" Enter
tmux split-window -t $SESSION_NAME
tmux send-keys -t $SESSION_NAME "$SETUP_ROS_STRING; sleep 3; export DISPLAY=${CURRENT_DISPLAY}; rosrun rviz rviz -d ${RVIZ_CONFIG_FILE}" Enter
tmux split-window -t $SESSION_NAME
tmux send-keys -t $SESSION_NAME "$SETUP_ROS_STRING; sleep 3; export DISPLAY=${CURRENT_DISPLAY}; rosparam set robot_name $MAV_NAME; rqt --standalone ${RQT_GUI}" Enter
# tmux split-window -t $SESSION_NAME
# tmux send-keys -t $SESSION_NAME "$SETUP_ROS_STRING; sleep 3; export DISPLAY=${CURRENT_DISPLAY}; rosbag record -a -O checking.bag" Enter
# tmux send-keys -t $SESSION_NAME "$SETUP_ROS_STRING; sleep 3; export DISPLAY=${CURRENT_DISPLAY}; rosbag record -a --split --duration=40 -O nn_lissajous.bag" Enter
tmux split-window -t $SESSION_NAME
tmux send-keys -t $SESSION_NAME "$SETUP_ROS_STRING; sleep 3; roslaunch kr_multi_mav_manager multi_mav_manager.launch odom_topic:=odom config_path:=$HOME/.ros/" Enter
tmux select-layout -t $SESSION_NAME tiled


# Add window to easily kill all processes
tmux new-window -t $SESSION_NAME -n "Kill"
tmux send-keys -t $SESSION_NAME "tmux kill-session -t ${SESSION_NAME}"

# Launch each mav in a new tmux window
for id in $(seq 1 $NUM_MAV)
do

  # Append rviz/Marker for cuurent mav id.
  MAV_NAME=${MAV_NAMESPACE}${id}
  sed -i "84a\    - Class: rviz/Marker\n      Enabled: true\n      Marker Topic: /quadrotor/mesh_visualization/robot\n      Name: quadrotor\n      Namespaces:\n        /quadrotor/mesh_visualization: true\n      Queue Size: 100\n      Value: true" ${RVIZ_CONFIG_FILE}
  sed -i "s/quadrotor/${MAV_NAME}/g" ${RVIZ_CONFIG_FILE}

  tmux new-window -t $SESSION_NAME -n "r${id}"

  # TODO generate poses on circle instead. Separated by robot size
  # Generate random poses x, y
  #POS_X=$(( $RANDOM % 10 ))
  #POS_Y=$(( $RANDOM % 10 ))

  # Generate poses on a grid
  row_i=$(( ( ( $id - 1 ) % $n_rows ) + 1 ))
  col_i=$(( ( ( $id - $row_i ) / $n_rows ) + 1 ))

  if [ "$CSV_INPUT" = true ]; then
    POS_X=${pos_val[${pos_cnt}]}
    POS_Y=${pos_val[$(expr ${pos_cnt} + 1)]}
    POS_Z=${pos_val[$(expr ${pos_cnt} + 2)]}
    POS_YAW=${pos_val[$(expr ${pos_cnt} + 3)]}
  else
    POS_X=$(( ( $col_i * $spacing ) + ( $spacing / 2 ) - $spacing ))
    POS_Y=$(( ( $row_i * $spacing ) + ( $spacing / 2 ) - $spacing ))
    POS_Z=0.0
    POS_YAW=0.0
  fi

  # Generate random colors [0-1]
  v=$[100 + (RANDOM % 100)]$[1000 + (RANDOM % 1000)]
  COL_R=0.${v:1:2}${v:4:3}
  v=$[100 + (RANDOM % 100)]$[1000 + (RANDOM % 1000)]
  COL_G=0.${v:1:2}${v:4:3}
  v=$[100 + (RANDOM % 100)]$[1000 + (RANDOM % 1000)]
  COL_B=0.${v:1:2}${v:4:3}
  COL_A=0.85

  tmux send-keys -t $SESSION_NAME "$SETUP_ROS_STRING; sleep 3; roslaunch kr_mav_launch demo.launch sim:=true vicon:=false mav_name:=${MAV_NAME} mav_type:=${MAV_TYPE} world_frame_id:=${WORLD_FRAME_ID} initial_position/x:=${POS_X} initial_position/y:=${POS_Y} initial_position/z:=${POS_Z} color/r:=${COL_R} color/g:=${COL_G} color/b:=${COL_B} color/a:=${COL_A}" Enter
  tmux split-window -t $SESSION_NAME
  tmux send-keys -t $SESSION_NAME "$SETUP_ROS_STRING; sleep 4; rosrun kr_trackers waypoints_to_action.py __ns:=${MAV_NAME}" Enter
  tmux split-window -t $SESSION_NAME
  tmux send-keys -t $SESSION_NAME "$SETUP_ROS_STRING; sleep 4; rosrun kr_trackers twist_to_velocity_goal.py __ns:=${MAV_NAME}" Enter
  tmux split-window -t $SESSION_NAME
  tmux send-keys -t $SESSION_NAME "$SETUP_ROS_STRING; sleep 4; rosrun layered_ref_control traj_${MAV_NAME}.py /${MAV_NAME}" Enter
  tmux new-window -t $SESSION_NAME -n "Record${id}"
  tmux send-keys -t $SESSION_NAME "$SETUP_ROS_STRING; sleep 4; rosrun layered_ref_control sync_msg _sim:=true _namespace:=${MAV_NAME} __name:=${MAV_NAME}" Enter
  tmux split-window -t $SESSION_NAME
  tmux send-keys -t $SESSION_NAME "$SETUP_ROS_STRING; sleep 4; cd $(rospack find kr_mav_launch)/scripts/; ./takeoff.sh ${MAV_NAME}"
  tmux select-layout -t $SESSION_NAME tiled



  let pos_cnt+=4
done

tmux select-window -t $SESSION_NAME:0
tmux -2 attach-session -t $SESSION_NAME