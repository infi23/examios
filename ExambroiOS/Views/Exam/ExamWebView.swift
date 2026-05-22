import SwiftUI
import WebKit

/// WKWebView wrapper dengan JS Bridge "ExambroNative"
struct ExamWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    var onCourseDetected: (String) -> Void
    var onQuizStateDetected: (String) -> Void
    var onMoodleUserDetected: (String) -> Void
    var studentId: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "ExambroNative")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent() // Clear cookies/cache setiap sesi

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (iPad; CPU OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Agrexambro/1.0.0"
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.scrollView.bounces = false

        // Bersihkan semua data web lama
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {}

        context.coordinator.webView = wv
        // Expose WKWebView ke ScreenshotService agar bisa di-snapshot dari ViewModel
        ScreenshotService.shared.webView = wv
        
        var request = URLRequest(url: url)
        let secret = ConfigManager.shared.moodleSecret
        if !secret.isEmpty {
            request.setValue(secret, forHTTPHeaderField: "X-Agrexambro-Key")
        }
        wv.load(request)
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: — Coordinator
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: ExamWebView
        weak var webView: WKWebView?

        init(_ parent: ExamWebView) { self.parent = parent }

        // MARK: JS Bridge
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let method = body["method"] as? String,
                  let arg = body["arg"] as? String else { return }
            DispatchQueue.main.async {
                switch method {
                case "onCourseNameDetected": self.parent.onCourseDetected(arg)
                case "onQuizStateDetected": self.parent.onQuizStateDetected(arg)
                case "onMoodleUserDetected": self.parent.onMoodleUserDetected(arg)
                case "reconnectMoodle":
                    let urlToLoad = self.webView?.url ?? self.parent.url
                    var request = URLRequest(url: urlToLoad)
                    let secret = ConfigManager.shared.moodleSecret
                    if !secret.isEmpty {
                        request.setValue(secret, forHTTPHeaderField: "X-Agrexambro-Key")
                    }
                    self.webView?.load(request)
                default: break
                }
            }
        }

        // MARK: Navigation
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            guard let url = webView.url?.absoluteString else { return }

            // URL-based status detection (parity dengan Android detectMoodleQuizStatus).
            // attempt.php = sedang aktif mengerjakan → set in_progress.
            let lower = url.lowercased()
            if lower.contains("/mod/quiz/attempt.php") {
                parent.onQuizStateDetected("in_progress")
            }

            injectScripts(webView: webView, url: url)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            webView.loadHTMLString(offlineHTML, baseURL: nil)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            webView.loadHTMLString(offlineHTML, baseURL: nil)
        }

        // MARK: JS Injections
        private func injectScripts(webView: WKWebView, url: String) {
            let lower = url.lowercased()

            // Inject 1: Scrape course short name dari breadcrumb
            webView.evaluateJavaScript(breadcrumbJS, completionHandler: nil)

            // Inject 2: Quiz state detection (view.php)
            if lower.contains("/mod/quiz/view.php") {
                webView.evaluateJavaScript(quizStateJS, completionHandler: nil)
            }

            // Inject 3: Auto-fill username Moodle
            if lower.contains("/login/index.php") || lower.contains("/login/") {
                let studentId = parent.studentId.replacingOccurrences(of: "'", with: "\\'")
                let autofillJS = """
                (function(){
                    var u=document.querySelector('input[name="username"]');
                    var p=document.querySelector('input[name="password"]');
                    if(u&&p){
                        u.value='\(studentId)';
                        u.dispatchEvent(new Event('input',{bubbles:true}));
                        u.setAttribute('readonly','true');
                        u.style.background='#f1f5f9';u.style.color='#475569';
                        p.focus();
                    }
                })();
                """
                webView.evaluateJavaScript(autofillJS, completionHandler: nil)
            }

            // Inject 4: Autosave error override
            webView.evaluateJavaScript(autosaveOverrideJS, completionHandler: nil)
        }

        private let breadcrumbJS = """
        (function(){
            var links=document.querySelectorAll('ol.breadcrumb .breadcrumb-item a');
            for(var i=0;i<links.length;i++){
                var link=links[i];
                var href=link.getAttribute('href')||'';
                var title=link.getAttribute('title')||'';
                if(href.indexOf('/my/')!==-1)continue;
                if(title.length>0){
                    var name=link.textContent.trim();
                    if(name)window.webkit.messageHandlers.ExambroNative.postMessage({method:'onCourseNameDetected',arg:name});
                    break;
                }
            }
        })();
        """

        private let quizStateJS = """
        (function(){
            var buttons=document.querySelectorAll('.quizattempt button,.quizstartbuttondiv button,form button[type="submit"]');
            var allText='';
            for(var i=0;i<buttons.length;i++) allText+=buttons[i].textContent.trim().toLowerCase()+'|';
            var finishedCell=document.querySelector('.quizattemptsummary td');
            var noMoreP=document.querySelector('.quizattempt p');
            var state='unknown';
            if((finishedCell&&finishedCell.textContent.indexOf('Finished')!==-1)||(noMoreP&&noMoreP.textContent.indexOf('No more attempts')!==-1)) state='finished';
            else if(allText.indexOf('continue')!==-1) state='in_progress';
            else if(allText.indexOf('attempt quiz')!==-1||allText.indexOf('attempt')!==-1) state='not_started';
            if(state!=='unknown') window.webkit.messageHandlers.ExambroNative.postMessage({method:'onQuizStateDetected',arg:state});
        })();
        """

        private let autosaveOverrideJS = """
        (function(){
            if(window.__exambroOverride)return;window.__exambroOverride=true;
            var html='<div style="background:#1e293b;border:1px solid #f59e0b;border-radius:12px;padding:16px;color:#fde68a;font-family:sans-serif;font-size:14px;line-height:1.6;margin:12px 0">⚠️ <strong>Penyimpanan Otomatis Tertunda</strong><br><span style="color:#fcd34d">Koneksi terputus. Jawaban akan tersimpan otomatis saat jaringan pulih.</span></div>';
            function check(el){
                if(!el||el.dataset.exFixed==='1')return false;
                var t=el.textContent||'';
                return t.indexOf('Autosave failed')!==-1||(t.indexOf('connection')!==-1&&t.indexOf('saved')!==-1&&t.length<600);
            }
            function fix(el){if(!el||el.dataset.exFixed==='1')return;el.dataset.exFixed='1';el.innerHTML=html;}
            function scan(){['#connection-error','.connectionerror','.alert-danger','[role="alert"]'].forEach(function(s){document.querySelectorAll(s).forEach(function(n){if(check(n))fix(n);});});}
            scan();new MutationObserver(scan).observe(document.body,{childList:true,subtree:true});
        })();
        """

        private var offlineHTML: String { ExamOfflineHTMLBuilder.build() }
    }
}
