#!/usr/bin/env python3

import asyncio
import os
import signal
import subprocess
import sys
import socket
import argparse
from collections import deque
import psutil
import signal

# Configuration
cache_dir_path = os.path.expanduser("~/.cache/nvim/")
server_pipe_path = os.path.expanduser("~/.cache/nvim/nvim-server-daemon.pipe")
log_file_path = os.path.expanduser("~/.cache/nvim/nvim-server-daemon.log")
socket_path = os.path.expanduser("~/.cache/nvim/nvim-server-daemon.sock")

# Queue to store client requests
request_queue = deque()

def cleanup(script_name, daemon_arg):
    """Kill the daemon if running, then clean up the server pipe, log file, and Unix socket."""
    # Kill the daemon first
    kill_daemon(script_name, daemon_arg)

    # Clean up by removing the server pipe, log file, and Unix socket
    clean_up_server_pipe()
    clean_up_socket()
    cleanup_log_file()

def cleanup_log_file():
    # Remove the log file if it exists
    if os.path.exists(log_file_path):
        os.remove(log_file_path)
        return True
    return False


def kill_daemon(script_name, daemon_arg):
    """Kill the daemon if it is running."""
    pid = get_daemon_pid(script_name, daemon_arg)
    if pid:
        print(f"Killing daemon with PID: {pid}")
        os.kill(pid, signal.SIGTERM)
    else:
        print("Daemon not running.")

# Ensure the ~/.cache/nvim/ directory exists
if not os.path.exists(cache_dir_path):
    os.makedirs(cache_dir_path)
    print(f"Created directory: {cache_dir_path}")

def clean_up_server_pipe():
    """Clean up by removing the server pipe."""
    if os.path.exists(server_pipe_path):
        os.remove(server_pipe_path)
    print("Cleaned up server pipe.")

def clean_up_socket():
    """Clean up by removing the Unix socket."""
    if os.path.exists(socket_path):
        os.remove(socket_path)
    print("Cleaned up Unix socket.")

def get_daemon_pid(script_name, daemon_arg):
    """Get the PID of the running daemon based on script name and daemon argument, excluding the current process."""
    current_pid = os.getpid()  # Get the PID of the current process
    print(f"Current PID: {current_pid}")  # Log current process PID
    try:
        for proc in psutil.process_iter(['pid', 'cmdline']):
            cmdline = proc.info['cmdline']
            pid = proc.info['pid']

            # Only log processes that have the script path in their cmdline
            if cmdline and script_name in ' '.join(cmdline):
                print(f"Checking process PID: {pid}, cmdline: {cmdline}")

            if cmdline and pid != current_pid:  # Exclude the current process
                # Check if the process is running the script with `python3` or directly
                if ('python3' in cmdline[0] and script_name in cmdline[1]) or os.path.basename(cmdline[0]) == script_name:
                    if daemon_arg in cmdline:  # Check if --daemon is in the cmdline
                        print(f"Daemon process found: {pid}, cmdline: {cmdline}")  # Log when daemon process is found
                        return pid
    except Exception as e:
        print(f"Error finding daemon PID: {e}")
    return None

def is_socket_in_use():
    """Check if the socket file is currently being used by any process."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client_socket:
            client_socket.connect(socket_path)
            return True
    except socket.error:
        return False

async def process_queue():
    """Process queued requests once the server is running."""
    while request_queue:
        filepath, line_number, column_number = request_queue.popleft()

        # Wait until the server is running before sending commands
        while not await check_server_pipe():
            await asyncio.sleep(0.1)

        open_file(filepath, line_number, column_number)

def signal_handler(sig, frame):
    global neovide_process

    # Clean up the server pipe and kill Neovide if it's running
    if neovide_process and neovide_process.poll() is None:
        neovide_process.terminate()
        neovide_process.wait()
    cleanup()
    sys.exit(0)

def open_server(filepath=None, line_number=0, column_number=0):
    """Start the Neovide server process without blocking."""
    
    # Determine the directory to change to
    if filepath:
        # If a file is provided, check if it's inside a git repository
        file_dir = os.path.dirname(filepath)
        try:
            git_root = subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], cwd=file_dir).decode().strip()
            os.chdir(git_root)
            print(f"Changed directory to git root: {git_root}")
        except subprocess.CalledProcessError:
            # If not in a git repo, change to the file's directory
            os.chdir(file_dir)
            print(f"Changed directory to file's directory: {file_dir}")
    else:
        # No file provided, just use the home directory or any default directory
        home_dir = os.path.expanduser("~")
        os.chdir(home_dir)
        print(f"Changed directory to home: {home_dir}")
    
    with open(log_file_path, "a") as log_file:
        env = os.environ.copy()
        env["NEOVIDE_MULTIGRID"] = "1"
        env["NEOVIDE_WM_CLASS"] = "nvide_daemon"  # WM rules from dwm/config.h
    
        if filepath:
            process = subprocess.Popen([
                "/usr/bin/neovide",
                "--",
                "--listen",
                server_pipe_path,
                filepath
            ], stdout=log_file, stderr=log_file, env=env)
        else:
            process = subprocess.Popen([
                "/usr/bin/neovide",
                "--",
                "--listen",
                server_pipe_path
            ], stdout=log_file, stderr=log_file, env=env)

    return process

def open_file(filepath=None, line_number=0, column_number=0):
    """Send the command to Neovim to open a file and move the cursor."""
    if filepath:
        subprocess.run([
            "nvim",
            "--server", server_pipe_path,
            "--remote-send",
            f":vs {filepath}<CR>:call cursor({line_number}, {column_number})<CR>"
        ])
    else:
        subprocess.run([
            "nvim",
            "--server", server_pipe_path,
            "--remote-send",
            f":vnew<CR>"
        ])

async def check_server_pipe():
    """Check if the server pipe is in use."""
    if not os.path.exists(server_pipe_path):
        print(f"Pipe {server_pipe_path} does not exist.")
        return False
    
    try:
        result = subprocess.run(
            ["lsof", "-U"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        is_in_use = "nvim" in result.stdout and server_pipe_path in result.stdout
        print(f"Pipe {server_pipe_path} check: {'in use' if is_in_use else 'not in use'}")
        return is_in_use
    except Exception as e:
        print(f"Error checking server pipe: {e}")
        return False

async def daemon():
    global neovide_process
    neovide_process = None  # Initialize here

    if os.path.exists(socket_path) and is_socket_in_use():
        print(f"Daemon already running. Exiting.")
        sys.exit(0)
    cleaned_log = cleanup_log_file()
    log_file = open(log_file_path, "a")
    sys.stdout = log_file
    sys.stderr = log_file
    if cleaned_log: print(f"Cleaned up log_file @ {log_file_path}")
    if os.path.exists(socket_path) and not is_socket_in_use():
        print(f"Socket exists but no running daemon found. Cleaning up and starting a new daemon.")
        clean_up_socket()


    # Register the cleanup function to be called on SIGINT and SIGTERM
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    try:
        # Create a Unix socket
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(socket_path)
        server.listen(1)
        print("Daemon is now running, waiting for client connections...")
        log_file.flush()  # Ensure the message is written immediately

        while True:
            conn, _ = server.accept()
            with conn:
                data = conn.recv(1024).decode().strip()
                if data:
                    print(f"Received event: {data}")
                    log_file.flush()  # Ensure the message is written immediately
                    parts = data.split()
                    
                    # Ensure we have three parts: filepath, line_number, and column_number
                    filepath = parts[0] if len(parts) > 0 else None
                    if filepath == "<NO_FILE>":
                        filepath = None  # Convert the marker to None
                    line_number = int(parts[1]) if len(parts) > 1 else 0
                    column_number = int(parts[2]) if len(parts) > 2 else 0

                    # Start Neovide if it's not already running
                    if not await check_server_pipe():
                        neovide_process = open_server(filepath, line_number, column_number)

                        # Ensure the server is up and running before processing any more commands
                        await asyncio.sleep(1)
                    else:
                        # If the server is already running, send the command to open the file
                        open_file(filepath, line_number, column_number)

    except socket.error as e:
        print(f"Daemon encountered an error: {e}")
        log_file.flush()  # Ensure the error message is written immediately
    finally:
        clean_up_socket()
        log_file.close()  # Ensure the file is closed

def client(filepath=None, line_number=0, column_number=0):
    """Client to send events to the daemon."""
    try:
        if filepath:
            # Remove any surrounding quotes
            filepath = filepath.strip('"').strip("'")
            # Expand ~ to home directory
            filepath = os.path.expanduser(filepath)
            # Convert to absolute path
            filepath = os.path.abspath(filepath)
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client_socket:
            client_socket.connect(socket_path)
            # Use a marker for no filename
            filepath = filepath or "<NO_FILE>"
            message = f"{filepath} {line_number} {column_number}"
            client_socket.sendall(message.encode())
            print(f"Sent event to daemon: {message}")
    except Exception as e:
        print(f"Failed to send event to daemon: {e}")

def main():
    parser = argparse.ArgumentParser(description="Neovim/Neovide Server Runner Daemon and Client")
    
    # Create a mutually exclusive group for --daemon and --client
    mode_group = parser.add_mutually_exclusive_group(required=False)
    mode_group.add_argument('--daemon', action='store_true', help="Run as daemon")
    mode_group.add_argument('--client', action='store_true', help="Run in client mode (default mode unless --daemon is specified)", default=True)

    # Arguments for killing the daemon
    kill_arg_names = ['-k', '--kill']
    parser.add_argument(*kill_arg_names, action='store_true', help="Kill the daemon if running")
    
    # Argument for cleaning up (implies --kill)
    parser.add_argument('--cleanup', action='store_true', help="Kill the daemon and clean up the server pipe, socket, and log file")

    # Positional arguments for client mode
    parser.add_argument(
        'filepath', 
        nargs='?', 
        help="File path to open (client mode, default=empty buffer)", 
        default=None
    )
    parser.add_argument('line_number', nargs='?', default=0, type=int, help="Line number (client mode, default=0)")
    parser.add_argument('column_number', nargs='?', default=0, type=int, help="Column number (client mode, default=0)")
    
    args = parser.parse_args()

    script_name = os.path.basename(__file__)

    if args.cleanup:
        # Cleanup implies --kill, so we kill the daemon and then clean up
        cleanup(script_name, '--daemon')
        sys.exit(0)

    match (args.daemon, args.kill, args.client):
        case (True, True, _):
            # Kill the daemon and restart it
            kill_daemon(script_name, '--daemon')
            print("Restarting daemon...")
            asyncio.run(daemon())

        case (False, True, _):
            # Just kill the daemon, ignore other arguments
            kill_daemon(script_name, '--daemon')

        case (True, False, _):
            # Only start the daemon if it's not already running
            pid = get_daemon_pid(script_name, '--daemon')
            if pid:
                print(f"Daemon already running with PID: {pid}. Exiting.")
                sys.exit(1)
            asyncio.run(daemon())

        case (False, False, True):
            # Run in client mode
            client(args.filepath, args.line_number, args.column_number)

if __name__ == "__main__":
    main()
