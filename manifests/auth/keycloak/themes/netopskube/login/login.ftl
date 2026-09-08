<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>${properties.appName!:"NetOpsKube"} Login</title>
    <style>
        * { box-sizing: border-box; }
        body {
            margin: 0;
            font-family: "Segoe UI", Arial, sans-serif;
            height: 100vh;
            overflow: hidden;
        }
        .box-container {
            display: flex;
            height: 100vh;
        }
        .left {
            width: 50%;
            background:
                radial-gradient(circle at 20% 30%, #00bfff 0%, transparent 35%),
                radial-gradient(circle at 80% 20%, #1f6feb 0%, transparent 40%),
                linear-gradient(135deg, #021124 0%, #0a192f 50%, #112240 100%);
            display: flex;
            align-items: flex-end;
            padding: 48px;
            color: #d9ecff;
        }
        .left-inner h1 {
            margin: 0 0 8px;
            font-size: 2rem;
            font-weight: 600;
        }
        .left-inner p {
            margin: 0;
            opacity: 0.85;
            max-width: 28rem;
            line-height: 1.5;
        }
        .right {
            width: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            background: #f5f7fb;
        }
        .rightcenterinner {
            width: 360px;
            padding: 32px;
            background: #fff;
            border-radius: 12px;
            box-shadow: 0 12px 40px rgba(10, 25, 47, 0.12);
            border: 1px solid rgba(31, 111, 235, 0.15);
        }
        .logintitle {
            margin-bottom: 24px;
            color: #1b3c59;
        }
        .logintitle .brand {
            font-size: 1.5rem;
            font-weight: 700;
            color: #124191;
        }
        .logintitle .subtitle {
            margin-top: 6px;
            font-size: 0.9rem;
            color: #5c6b7a;
        }
        .label {
            display: block;
            color: #5c6b7a;
            font-size: 0.75rem;
            font-weight: 700;
            margin-bottom: 6px;
            text-transform: uppercase;
            letter-spacing: 0.04em;
        }
        .login-field {
            width: 100%;
            border: 1px solid #d0d7de;
            border-radius: 6px;
            padding: 10px 12px;
            margin-bottom: 16px;
            font-size: 0.95rem;
        }
        .login-field:focus {
            outline: none;
            border-color: #1f6feb;
            box-shadow: 0 0 0 3px rgba(31, 111, 235, 0.15);
        }
        .buttoncontainer {
            display: flex;
            justify-content: flex-end;
            margin-top: 8px;
        }
        .nokiabutton {
            border: none;
            border-radius: 4px;
            background: #124191;
            color: #fff;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.03em;
            padding: 10px 18px;
            cursor: pointer;
            min-width: 110px;
        }
        .nokiabutton:disabled {
            background: #ccc;
            color: #777;
            cursor: default;
        }
        .error-message {
            color: #d93025;
            font-size: 0.9rem;
            margin-bottom: 12px;
        }
    </style>
</head>
<body>
<div class="box-container">
    <div class="left">
        <div class="left-inner">
            <h1>${properties.appName!:"NetOpsKube"}</h1>
            <p>Network observability and operations portal. Sign in to access Grafana, Prometheus, GitOps, and recipe dashboards.</p>
        </div>
    </div>
    <div class="right">
        <div class="rightcenterinner">
            <div class="logintitle">
                <div class="brand">Sign in</div>
                <div class="subtitle">Use your NetOpsKube account</div>
            </div>
            <form id="kc-form-login" action="${url.loginAction}" method="post">
                <label class="label" for="username">Username</label>
                <input id="username" class="login-field" type="text" name="username"
                       value="${(login.username!'')}" autocomplete="username" required autofocus
                       oninput="updateSubmit()">
                <label class="label" for="password">Password</label>
                <input id="password" class="login-field" type="password" name="password"
                       autocomplete="current-password" required oninput="updateSubmit()">
                <#if message?has_content>
                    <div class="error-message">${kcSanitize(message.summary)?no_esc}</div>
                </#if>
                <div class="buttoncontainer">
                    <button id="submitbutton" class="nokiabutton" type="submit" disabled>Log in</button>
                </div>
            </form>
        </div>
    </div>
</div>
<script>
function updateSubmit() {
    const u = document.getElementById("username").value;
    const p = document.getElementById("password").value;
    document.getElementById("submitbutton").disabled = !u || !p;
}
updateSubmit();
</script>
</body>
</html>
