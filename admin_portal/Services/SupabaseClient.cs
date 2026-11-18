using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.Extensions.Options;

namespace AdminPortal.Services;

public class SupabaseOptions
{
    public string Url { get; set; } = "";
    public string AnonKey { get; set; } = "";
}

/// <summary>Error returned by Supabase, with a message that is safe to show the user (FR-021).</summary>
public class SupabaseException(string message) : Exception(message);

public class AuthUser
{
    public string Id { get; set; } = "";
    public string Email { get; set; } = "";
}

public class AuthSession
{
    public string AccessToken { get; set; } = "";
    public string RefreshToken { get; set; } = "";
    public long ExpiresAt { get; set; }   // unix seconds
    public AuthUser User { get; set; } = new();
}

/// <summary>
/// The "API Request (HTTPS) / Response (JSON)" arrows on the architecture diagram.
///   Auth     -> {Url}/auth/v1/...      (Supabase Authentication)
///   Database -> {Url}/rest/v1/...      (PostgREST over the Supabase Database)
///   Storage  -> {Url}/storage/v1/...   (Supabase Storage)
/// Every data call is sent with the signed-in admin's JWT, so Row Level Security applies.
/// </summary>
public class SupabaseClient(HttpClient http, IOptions<SupabaseOptions> options, IHttpContextAccessor ctx)
{
    private readonly SupabaseOptions _opt = options.Value;

    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,   // EventId <-> event_id
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    // ------------------------------------------------------------------ Auth

    public Task<AuthSession> SignInAsync(string email, string password) =>
        AuthPostAsync<AuthSession>("token?grant_type=password", new { email, password });

    public Task<JsonElement> SignUpAsync(string email, string password, Dictionary<string, string> metadata) =>
        AuthPostAsync<JsonElement>("signup", new Dictionary<string, object>
        {
            ["email"] = email, ["password"] = password, ["data"] = metadata,
        });

    public Task<JsonElement> SendPasswordResetAsync(string email) =>
        AuthPostAsync<JsonElement>("recover", new { email });

    private Task<AuthSession> RefreshAsync(string refreshToken) =>
        AuthPostAsync<AuthSession>("token?grant_type=refresh_token",
            new Dictionary<string, string> { ["refresh_token"] = refreshToken });

    private async Task<T> AuthPostAsync<T>(string path, object body)
    {
        using var req = new HttpRequestMessage(HttpMethod.Post, $"{_opt.Url}/auth/v1/{path}")
        {
            Content = JsonContent(body),
        };
        req.Headers.Add("apikey", _opt.AnonKey);
        return await SendAsync<T>(req);
    }

    /// Builds the cookie principal after login (and after a token refresh).
    public static ClaimsPrincipal BuildPrincipal(AuthSession s, string role, string displayName)
    {
        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, s.User.Id),
            new(ClaimTypes.Email, s.User.Email),
            new(ClaimTypes.Name, displayName),
            new(ClaimTypes.Role, role),
            new("sb_access_token", s.AccessToken),
            new("sb_refresh_token", s.RefreshToken),
            new("sb_expires_at", s.ExpiresAt.ToString()),
        };
        return new ClaimsPrincipal(new ClaimsIdentity(claims, CookieAuthenticationDefaults.AuthenticationScheme));
    }

    /// Returns a valid access token for the current admin, refreshing it if it expired (tokens last 1 hour).
    private async Task<string> AccessTokenAsync()
    {
        var httpContext = ctx.HttpContext;
        var user = httpContext?.User;
        if (user?.Identity?.IsAuthenticated != true) return _opt.AnonKey;

        var token = user.FindFirstValue("sb_access_token") ?? "";
        var expiresAt = long.TryParse(user.FindFirstValue("sb_expires_at"), out var e) ? e : 0;
        if (DateTimeOffset.UtcNow.ToUnixTimeSeconds() < expiresAt - 60) return token;

        var refreshed = await RefreshAsync(user.FindFirstValue("sb_refresh_token") ?? "");
        var principal = BuildPrincipal(refreshed, user.FindFirstValue(ClaimTypes.Role) ?? "",
                                       user.FindFirstValue(ClaimTypes.Name) ?? "");
        await httpContext!.SignInAsync(CookieAuthenticationDefaults.AuthenticationScheme, principal);
        httpContext.User = principal;
        return refreshed.AccessToken;
    }

    // -------------------------------------------------------------- Database

    /// GET /rest/v1/{query}   e.g. "events?select=*&order=event_date.desc"
    public async Task<List<T>> GetAsync<T>(string query)
    {
        using var req = await DataRequestAsync(HttpMethod.Get, $"rest/v1/{query}");
        return await SendAsync<List<T>>(req);
    }

    public async Task<T?> GetOneAsync<T>(string query) => (await GetAsync<T>(query)).FirstOrDefault();

    /// INSERT a row and return it (Prefer: return=representation)
    public async Task<T> InsertAsync<T>(string table, object row)
    {
        using var req = await DataRequestAsync(HttpMethod.Post, $"rest/v1/{table}", row);
        req.Headers.Add("Prefer", "return=representation");
        var rows = await SendAsync<List<T>>(req);
        return rows.First();
    }

    /// PATCH rows matching a filter, e.g. UpdateAsync("events?event_id=eq.5", new { title = "x" })
    public async Task UpdateAsync(string tableAndFilter, object patch)
    {
        using var req = await DataRequestAsync(HttpMethod.Patch, $"rest/v1/{tableAndFilter}", patch);
        req.Headers.Add("Prefer", "return=minimal");
        await SendAsync<JsonElement>(req);
    }

    /// DELETE rows matching a filter, e.g. DeleteAsync("coupons?coupon_id=eq.5")
    public async Task DeleteAsync(string tableAndFilter)
    {
        using var req = await DataRequestAsync(HttpMethod.Delete, $"rest/v1/{tableAndFilter}");
        req.Headers.Add("Prefer", "return=minimal");
        await SendAsync<JsonElement>(req);
    }

    /// Calls a database function from 02_functions.sql, e.g. record_attendance
    public async Task<T> RpcAsync<T>(string function, object? args = null)
    {
        using var req = await DataRequestAsync(HttpMethod.Post, $"rest/v1/rpc/{function}", args ?? new { });
        return await SendAsync<T>(req);
    }

    // --------------------------------------------------------------- Storage

    /// Uploads a file to a public bucket and returns its public URL.
    public async Task<string> UploadPublicAsync(string bucket, string path, Stream content, string contentType)
    {
        using var req = await DataRequestAsync(HttpMethod.Post, $"storage/v1/object/{bucket}/{path}");
        req.Content = new StreamContent(content);
        req.Content.Headers.ContentType = new MediaTypeHeaderValue(contentType);
        req.Headers.Add("x-upsert", "true");
        await SendAsync<JsonElement>(req);
        return $"{_opt.Url}/storage/v1/object/public/{bucket}/{path}";
    }

    // --------------------------------------------------------------- Helpers

    private async Task<HttpRequestMessage> DataRequestAsync(HttpMethod method, string path, object? body = null)
    {
        var req = new HttpRequestMessage(method, $"{_opt.Url}/{path}");
        req.Headers.Add("apikey", _opt.AnonKey);
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", await AccessTokenAsync());
        if (body != null) req.Content = JsonContent(body);
        return req;
    }

    private static StringContent JsonContent(object body) =>
        new(JsonSerializer.Serialize(body, Json), Encoding.UTF8, "application/json");

    private async Task<T> SendAsync<T>(HttpRequestMessage req)
    {
        HttpResponseMessage res;
        try
        {
            res = await http.SendAsync(req);
        }
        catch (HttpRequestException)
        {
            throw new SupabaseException("Cannot reach the server. Check your internet connection and try again.");
        }

        var text = await res.Content.ReadAsStringAsync();
        if (!res.IsSuccessStatusCode) throw new SupabaseException(ExtractError(text, (int)res.StatusCode));
        if (string.IsNullOrWhiteSpace(text)) return default!;
        return JsonSerializer.Deserialize<T>(text, Json)!;
    }

    /// Supabase Auth returns {"msg"} / {"error_description"}; the database returns {"message"}.
    private static string ExtractError(string body, int status)
    {
        try
        {
            using var doc = JsonDocument.Parse(body);
            foreach (var key in new[] { "message", "msg", "error_description", "error" })
                if (doc.RootElement.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String)
                {
                    var m = v.GetString()!;
                    if (m.Contains("Invalid login credentials")) return "Incorrect staff number/email or password.";
                    if (m.Contains("Email not confirmed")) return "Confirm your email first: open the link Supabase sent to your inbox, then log in.";
                    if (m.Contains("staff_number_key") || (m.Contains("Staff number") && m.Contains("already registered")))
                        return "That staff number is already registered. Log in instead, or use a different staff number.";
                    if (m.Contains("event_administrators_email_key") || m.Contains("cafeteria_staff_email_key")
                        || m.Contains("User already registered"))
                        return "An account with that email already exists. Please log in instead.";
                    if (m.Contains("Database error saving new user"))
                        return "Registration failed. Staff must use a @cut.ac.za email address, and the staff number must be unique.";
                    if (m.Contains("JWT expired")) return "Your session expired. Please log in again.";
                    if (m.Contains("redemptions_coupon_id_fkey"))
                        return "Students have already redeemed this, so it can't be deleted (the records must be kept). Switch it off instead.";
                    if (m.Contains("row-level security") && m.Contains("coupons"))
                        return "You are not allowed to change this coupon. Cafeteria staff can only manage Food (meal) coupons.";
                    return m;
                }
        }
        catch (JsonException) { }
        return $"Request failed ({status}).";
    }
}
