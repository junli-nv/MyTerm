import Foundation
import Darwin

public enum ChildProcessCleanup {
    /// SwiftTerm 1.x cancels its exit monitor on terminate(), so explicitly reap that child.
    /// waitpid confirms ownership before any fallback signal; unrelated PIDs are never signalled.
    public static func reap(_ pid: pid_t) {
        guard pid > 0 else { return }
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 0
            for _ in 0..<20 {
                let result = waitpid(pid, &status, WNOHANG)
                if result == pid || (result == -1 && errno != EINTR) { return }
                usleep(50_000)
            }
            guard waitpid(pid, &status, WNOHANG) == 0 else { return }
            kill(pid, SIGKILL)
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        }
    }
}
