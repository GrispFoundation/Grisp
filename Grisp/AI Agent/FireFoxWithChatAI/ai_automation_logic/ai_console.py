import socket
import json
import sys
import argparse

def send_command(cmd, port=9999):
    try:
        with socket.create_connection(('localhost', port)) as s:
            s.sendall((json.dumps(cmd) + "\n").encode('utf-8'))

            response_data = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                response_data += chunk
                if b"\n" in response_data:
                    break

            return json.loads(response_data.decode('utf-8'))
    except ConnectionRefusedError:
        print("Error: Could not connect to Firefox. Make sure it is running and the AIAutomation component is active.")
        sys.exit(1)
    except Exception as e:
        print(f"An error occurred: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description='AI Automation Console Tool')
    parser.add_argument('--port', type=int, default=9999, help='Port Firefox is listening on')
    
    # Action groups
    group = parser.add_argument_group('Actions')
    group.add_argument('--prompt', help='The chat prompt to send')
    group.add_argument('--list-tabs', action='store_true', help='List all open tabs')
    group.add_argument('--open-url', help='Open a URL in a new tab')
    group.add_argument('--duplicate', action='store_true', help='Duplicate tab specified by --tab')
    group.add_argument('--close', action='store_true', help='Close tab specified by --tab')

    # Parameters
    params = parser.add_argument_group('Parameters')
    params.add_argument('--site', help='The AI website/model to use (required for --prompt if --tab is not used)')
    params.add_argument('--tab', help='Index, Title, or URL of the tab to re-use or manage')

    args = parser.parse_args()

    if args.list_tabs:
        resp = send_command({"command": "getTabs"}, args.port)
        if "tabs" in resp:
            print(f"{'Index':<6} {'Selected':<10} {'Title':<40} {'URL'}")
            print("-" * 100)
            for tab in resp["tabs"]:
                sel = "*" if tab["selected"] else ""
                print(f"{tab['index']:<6} {sel:<10} {tab['title'][:38]:<40} {tab['url']}")
        else:
            print(resp)

    elif args.open_url:
        resp = send_command({"command": "openTab", "url": args.open_url}, args.port)
        print(resp)

    elif args.duplicate:
        if args.tab is None:
            print("Error: --tab is required for --duplicate")
            sys.exit(1)
        resp = send_command({"command": "duplicateTab", "tab": args.tab}, args.port)
        print(resp)

    elif args.close:
        if args.tab is None:
            print("Error: --tab is required for --close")
            sys.exit(1)
        resp = send_command({"command": "closeTab", "tab": args.tab}, args.port)
        print(resp)

    elif args.prompt:
        if not args.site and args.tab is None:
            print("Error: --site or --tab is required for --prompt")
            sys.exit(1)
        
        cmd = {
            "command": "prompt",
            "site": args.site,
            "text": args.prompt,
            "tab": args.tab if args.tab is not None else -1
        }
        resp = send_command(cmd, args.port)
        
        if "error" in resp:
            print(f"Error: {resp['error']}")
            if "lastSeen" in resp:
                print(f"Last seen text: {resp['lastSeen']}")
        else:
            print(resp.get("text", "No response text received."))
    
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
