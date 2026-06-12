# airflow-ko-pr-notifier

apache/airflow 저장소를 폴링해서 Discord 웹훅으로 알림을 보냅니다:

1. `translation:ko` 라벨이 붙은 open PR 중 아직 알리지 않은 것 (리뷰 요청)
   — 새 PR뿐 아니라 기존에 열려 있던 PR, 라벨이 나중에 붙은 PR도 포함됩니다.
2. main 브랜치에서 en 로케일 폴더(`airflow-core/src/airflow/ui/public/i18n/locales/en`)를
   변경한 새 커밋 — ko 폴더 동기화가 필요한 신호이며, 변경된 파일 목록을 함께 보냅니다.

## 동작 방식

- GitHub Actions가 15분마다 (`*/15 * * * *`) 실행됩니다.
- PR은 GitHub Search API(`is:pr is:open label:"translation:ko"`)로, en 변경은
  Commits API(`path=` + `since=`)로 조회합니다.
- 알린 PR 번호와 커밋 SHA는 `state.json`에 기록되어 중복 알림을 방지합니다.

## 설정

Discord 웹훅 URL을 repo secret으로 등록해야 합니다:

```sh
gh secret set DISCORD_WEBHOOK_URL -R choo121600/airflow-ko-pr-notifier
```

수동 실행으로 테스트:

```sh
gh workflow run notify.yml -R choo121600/airflow-ko-pr-notifier
```

> 참고: GitHub Actions의 schedule cron은 부하에 따라 수 분 지연될 수 있습니다.
> 또한 60일간 레포에 활동이 없으면 scheduled workflow가 자동 비활성화되는데,
> 이 워크플로는 새 PR을 발견할 때마다 `state.json`을 커밋하므로 평소엔 해당되지 않습니다.
