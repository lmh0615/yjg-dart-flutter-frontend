import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:yjg/auth/data/models/token_response.dart';
import 'package:yjg/auth/domain/usecases/domain_validation_usecase.dart';
import 'package:yjg/auth/presentation/viewmodels/user_viewmodel.dart';
import 'package:yjg/main.dart';
import 'package:yjg/shared/constants/api_url.dart';

class GoogleLoginDataSource {
  // 상수 파일에서 가져온 apiURL 사용
  String getApiUrl() {
    return apiURL;
  }

  // 구글 로그인
  static final _googleSignin = GoogleSignIn(
    scopes: <String>[
      'email',
    ],
  );

  // 구글 로그인 통신
  Future<void> signInWithGoogle(WidgetRef ref, BuildContext context) async {
    try {
      await _googleSignin.signIn();
      final GoogleSignInAccount? account = _googleSignin.currentUser;
      final domainValidationUseCase = DomainValidationUseCase();

      if (account != null) {
        // 이메일 도메인 검증
        if (!domainValidationUseCase(account.email)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('학교 이메일(@g.yju.ac.kr)이 아닐 경우 로그인을 할 수 없습니다.'),
              backgroundColor: Colors.red,
            ),
          );
          await _googleSignin.disconnect(); // 로그인 실패 시 연결 해제
          return;
        }

        GoogleSignInAuthentication googleAuth = await account.authentication;

        // Riverpod를 통해 User 상태를 업데이트
        ref.read(userProvider.notifier).updateWithGoogleSignIn(
              email: account.email,
              displayName: account.displayName,
              idToken: googleAuth.accessToken,
            );

        debugPrint("Google User Token: ${googleAuth.accessToken}");
        debugPrint('구글 계정 정보: $account');
        await postGoogleLoginAPI(ref);
      }
    } catch (error) {
      debugPrint('Error signing in with Google: $error');
    }
  }

  // 토큰 담는 곳
  static final storage = FlutterSecureStorage();

  // 구글 로그인 후 토큰 교환 통신
  Future<http.Response> postGoogleLoginAPI(WidgetRef ref) async {
    final loginState = ref.read(userProvider.notifier);
    final deviceInfo = await storage.read(key: 'deviceType');
    final body = jsonEncode(<String, String>{
      'email': loginState.email,
      'displayName': loginState.displayName,
      'id_token': loginState.idToken,
      'os_type': deviceInfo ?? 'unknown',
    });

    debugPrint('내가 보내려는 값: $body');
    final response = await http.post(Uri.parse('$apiURL/api/user/google-login'),
        headers: <String, String>{
          'Content-Type': 'application/json',
        },
        body: body);

    debugPrint(
        "postGoogleLoginAPI 토큰 교환 결과: ${jsonDecode(utf8.decode(response.bodyBytes))}, ${response.statusCode}");

    if (response.statusCode == 403) {
      navigatorKey.currentState!
          .pushNamed('/registration_detail'); // 추가 정보 입력 페이지로 이동
    }
    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body);
      Tokengenerated result = Tokengenerated.fromJson(jsonData);

      int? id = result.user?.id; // 응답으로부터 사용자 ID 추출
      int? approved = result.user?.approved;
      if (id != null) {
        // 새 사용자 ID로 상태 업데이트
        ref.read(userIdProvider.notifier).setUserId(id);
      } else {
        // ID가 null인 경우 처리
        debugPrint('사용자 ID가 null입니다.');
      }

      String? token = result.accessToken; // 응답으로부터 토큰 추출

      if (token != null) {
        // 토큰을 저장하기 위해 사용
        await storage.write(key: 'auth_token', value: token);
        await storage.write(key: 'studentName', value: loginState.displayName);
      } else {
        // 토큰이 null인 경우 처리
        debugPrint('토큰이 없습니다.');
      }
      return response;
    } else {
      throw Exception('로그인 실패: ${response.statusCode}');
    }
  }

  // 구글 로그아웃
  static Future<void> logout() => _googleSignin.signOut();
}
